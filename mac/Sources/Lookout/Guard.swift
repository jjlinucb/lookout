import AppKit
import CoreVideo
import Foundation
import LookoutCore

/// The heavy work, off the main thread: what changed, the detector, and
/// talking to browsers. Only coarse samples of the screen are kept.
actor Worker {
    let detector: Detector
    var tracker = ChangeTracker()
    private var urlCache: (id: String, at: Date, url: String?) = ("", .distantPast, nil)

    init(detector: Detector) { self.detector = detector }

    func check(_ frames: [CVPixelBuffer]) -> [Hit] {
        var hits: [Hit] = []
        for (i, frame) in frames.enumerated() {
            CVPixelBufferLockBaseAddress(frame, .readOnly)
            let w = CVPixelBufferGetWidth(frame), h = CVPixelBufferGetHeight(frame)
            guard let base = CVPixelBufferGetBaseAddress(frame) else {
                CVPixelBufferUnlockBaseAddress(frame, .readOnly)
                continue
            }
            let grid = Grid.sample(bgra: base, bytesPerRow: CVPixelBufferGetBytesPerRow(frame),
                                   width: w, height: h, step: ChangeTracker.step)
            CVPixelBufferUnlockBaseAddress(frame, .readOnly)
            hits += tracker.look(display: i, grid: grid, frameWidth: w, frameHeight: h) { region in
                detector.scan(frame, region: region)
            }
        }
        return hits
    }

    func forget() { tracker.forget() }

    /// Asking a browser costs an Apple event, so at most every 3 seconds, or
    /// every look while there are pages to redirect.
    func url(of id: String, maxAge: Double = 3) -> String? {
        guard Browser.chromium.contains(id) || Browser.safari.contains(id) else { return nil }
        if id != urlCache.id || Date().timeIntervalSince(urlCache.at) > maxAge {
            urlCache = (id, Date(), Browser.url(of: id))
        }
        return urlCache.url
    }

    func close(_ app: NSRunningApplication) -> String { Browser.close(app) }

    func go(_ id: String, to target: String) -> Bool {
        urlCache.at = .distantPast
        return Browser.go(id, to: target)
    }
}

/// The loop: look once a second, judge, and cover the screen when it counts.
@MainActor
final class Guard {
    let settings: Settings
    let log: EventLog
    var state: GuardState
    var judge: Judge
    let worker: Worker
    let capture = Capture()
    let cover = Cover()
    let curfewScreen = CurfewScreen()
    private var lastPass: Date?
    private var warnedAt = Date.distantPast
    var onStateChange: () -> Void = {}
    private var dismissed = false
    private var warnedNoPermission = Date.distantPast

    init(settings: Settings, log: EventLog, detector: Detector) {
        self.settings = settings
        self.log = log
        state = GuardState(log: log, pauseMinutes: settings.pauseMinutes)
        judge = Judge(settings)
        worker = Worker(detector: detector)
        cover.onContinue = { [weak self] in self?.dismissed = true }
        lastPass = lastCurfewPass(log.read())
        curfewScreen.onPass = { [weak self] in
            guard let self, let c = settings.curfew else { return }
            lastPass = Date()
            log.append(Event(verdict: "curfew pass", action: "working late: \(c.passMinutes) min"))
            curfewScreen.hide()
        }
        cover.onWrongFlag = { [weak self] in
            guard let self else { return }
            state.pause()
            dismissed = true
            onStateChange()
        }
    }

    func toggle() {
        state.toggle()
        judge.reset()
        onStateChange()
    }

    func pauseFromMenu(minutes: Double) {
        state.pauseFromMenu(minutes: minutes)
        judge.reset()
        onStateChange()
    }

    func start() { Task { await loop() } }

    private func loop() async {
        while true {
            let started = Date()
            await pass()
            let left = settings.intervalSeconds - Date().timeIntervalSince(started)
            if left > 0 { try? await Task.sleep(nanoseconds: UInt64(left * 1e9)) }
        }
    }

    private func pass() async {
        // Redirects are a restriction, not a check, so a pause doesn't stop them.
        if await redirected() { return }
        // Neither Turn Off nor a wrong-flag pause lifts the curfew; only the pass does.
        if curfewUp() {
            judge.reset()
            return
        }
        guard state.shouldCheck() else {
            judge.reset()
            await worker.forget()
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        let id = front?.bundleIdentifier ?? ""
        let url = await worker.url(of: id)
        if isSkipped(bundleID: id, url: url, settings: settings) {
            judge.reset()
            return
        }
        guard Capture.allowed else {
            if Date().timeIntervalSince(warnedNoPermission) > 3600 {
                warnedNoPermission = Date()
                log.append(Event(verdict: "no-permission", action: "screen recording not allowed"))
                onStateChange()
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            return
        }
        let frames: [CVPixelBuffer]
        do { frames = try await capture.frames() } catch { return }
        let hits = await worker.check(frames)
        let night = settings.curfew?.isNight(at: Date()) ?? false
        if let (verdict, reasons) = judge.judge(hits, night: night) {
            var backgrounds: [CGDirectDisplayID: CGImage] = [:]
            for (id, frame) in zip(capture.displayIDs, frames) { backgrounds[id] = Cover.blurred(frame) }
            await handle(verdict, reasons, backgrounds: backgrounds)
        }
    }

    /// Shows or lifts the curfew screen and the notice before it. True while it's up.
    private func curfewUp() -> Bool {
        guard let c = settings.curfew else { return false }
        switch c.state(at: Date(), lastPass: lastPass) {
        case .night:
            if !curfewScreen.isShown { log.append(Event(verdict: "curfew", action: "screen up until \(c.end)")) }
            curfewScreen.show(until: c.end, passMinutes: c.passMinutes)
            return true
        case .warn:
            if Date().timeIntervalSince(warnedAt) > Double(c.warnMinutes + 1) * 60 {
                warnedAt = Date()
                curfewScreen.showNotice("Curfew at \(c.start). Time to wrap up.")
            }
        case .pass, .off:
            break
        }
        curfewScreen.hide()
        return false
    }

    /// Sends the front tab away from a page in `redirectPages`. True if it did.
    private func redirected() async -> Bool {
        guard !settings.redirectPages.isEmpty, let front = NSWorkspace.shared.frontmostApplication,
              let id = front.bundleIdentifier else { return false }
        let url = await worker.url(of: id, maxAge: 0.5)
        guard let target = redirect(for: url, settings: settings) else { return false }
        let ok = await worker.go(id, to: target)
        log.append(Event(verdict: "redirect", app: front.localizedName ?? "", domain: domain(of: url),
                         action: ok ? "sent to \(domain(of: target) ?? "")" : "redirect failed"))
        return true
    }

    private func handle(_ verdict: Verdict, _ reasons: [Hit], backgrounds: [CGDirectDisplayID: CGImage] = [:]) async {
        let app = NSWorkspace.shared.frontmostApplication
        let id = app?.bundleIdentifier ?? ""
        let site = Browser.isBrowser(id) ? domain(of: await worker.url(of: id)) : nil
        dismissed = false
        cover.show("Blocked. That was taken off your screen.", pauseMinutes: Int(settings.pauseMinutes),
                   backgrounds: backgrounds)
        var action = "covered only"
        if shouldClose(verdict, reasons, settings: settings), let app { action = await worker.close(app) }
        log.append(Event(verdict: verdict.rawValue, app: app?.localizedName ?? "", domain: site, action: action, hits: reasons))
        let until = Date().addingTimeInterval(settings.coverSeconds)
        while !dismissed && Date() < until { try? await Task.sleep(nanoseconds: 100_000_000) }
        cover.hide()
        await worker.forget()
    }

    /// For trying the cover without anything on screen: `Lookout --test-cover`.
    func testCover() async {
        dismissed = false
        var backgrounds: [CGDirectDisplayID: CGImage] = [:]
        if Capture.allowed, let frames = try? await capture.frames() {
            for (id, frame) in zip(capture.displayIDs, frames) { backgrounds[id] = Cover.blurred(frame) }
        }
        cover.show("Test: this is what a block looks like.", pauseMinutes: Int(settings.pauseMinutes),
                   backgrounds: backgrounds)
        log.append(Event(verdict: "test", action: "test cover"))
        let until = Date().addingTimeInterval(settings.coverSeconds)
        while !dismissed && Date() < until { try? await Task.sleep(nanoseconds: 100_000_000) }
        cover.hide()
    }
}
