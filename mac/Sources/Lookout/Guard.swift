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

    /// Asking a browser costs an Apple event, so at most every 3 seconds.
    func url(of id: String) -> String? {
        guard Browser.chromium.contains(id) || Browser.safari.contains(id) else { return nil }
        if id != urlCache.id || Date().timeIntervalSince(urlCache.at) > 3 {
            urlCache = (id, Date(), Browser.url(of: id))
        }
        return urlCache.url
    }

    func close(_ app: NSRunningApplication) -> String { Browser.close(app) }
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
        if let (verdict, reasons) = judge.judge(hits) {
            await handle(verdict, reasons)
        }
    }

    private func handle(_ verdict: Verdict, _ reasons: [Hit]) async {
        let app = NSWorkspace.shared.frontmostApplication
        let id = app?.bundleIdentifier ?? ""
        let site = Browser.isBrowser(id) ? domain(of: await worker.url(of: id)) : nil
        dismissed = false
        cover.show("Blocked. That was taken off your screen.", pauseMinutes: Int(settings.pauseMinutes))
        var action = "covered only"
        if settings.closeTab, let app { action = await worker.close(app) }
        log.append(Event(verdict: verdict.rawValue, app: app?.localizedName ?? "", domain: site, action: action, hits: reasons))
        let until = Date().addingTimeInterval(settings.coverSeconds)
        while !dismissed && Date() < until { try? await Task.sleep(nanoseconds: 100_000_000) }
        cover.hide()
        await worker.forget()
    }

    /// For trying the cover without anything on screen: `Lookout --test-cover`.
    func testCover() async {
        dismissed = false
        cover.show("Test: this is what a block looks like.", pauseMinutes: Int(settings.pauseMinutes))
        log.append(Event(verdict: "test", action: "test cover"))
        let until = Date().addingTimeInterval(settings.coverSeconds)
        while !dismissed && Date() < until { try? await Task.sleep(nanoseconds: 100_000_000) }
        cover.hide()
    }
}
