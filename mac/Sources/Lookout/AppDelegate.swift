import AppKit
import LookoutCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lookout")

    let log = EventLog(folder: AppDelegate.support)
    var guardian: Guard?
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var blockingBusy = false

    func applicationDidFinishLaunching(_ note: Notification) {
        // One Lookout at a time.
        let me = ProcessInfo.processInfo.processIdentifier
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains(where: { $0.processIdentifier != me }) {
            NSApp.terminate(nil)
            return
        }
        // A guard must never be quit by macOS to save memory.
        ProcessInfo.processInfo.disableAutomaticTermination("Lookout is guarding")
        ProcessInfo.processInfo.disableSuddenTermination()
        menu.delegate = self
        menu.autoenablesItems = false
        status.menu = menu
        rebuildMenu()

        let settings = Settings.load(from: Self.support.appendingPathComponent("settings.json"))
        do {
            let model = Bundle.main.url(forResource: "NudeNet320n", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "NudeNet320n", withExtension: "mlpackage")
            guard let model else { throw NSError(domain: "Lookout", code: 2, userInfo: [NSLocalizedDescriptionKey: "model missing"]) }
            let g = Guard(settings: settings, log: log, detector: try Detector(bundled: model, cache: Self.support))
            g.onStateChange = { [weak self] in self?.rebuildMenu() }
            guardian = g
        } catch {
            log.append(Event(verdict: "error", action: "detector failed to load: \(error.localizedDescription)"))
        }
        log.append(Event(verdict: "started", action: "app launched"))

        if CommandLine.arguments.contains("--test-cover") {
            Task { await guardian?.testCover() }
        }
        if !Capture.allowed { Capture.ask() }
        // Start at login. It shows under System Settings > General > Login Items.
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        guardian?.start()
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    func rebuildMenu() {
        let on = guardian?.state.on ?? false
        let paused = (guardian?.state.pausedUntil ?? .distantPast) > Date()
        let image = NSImage(systemSymbolName: on ? "eye" : "eye.slash", accessibilityDescription: "Lookout")
        image?.isTemplate = true
        status.button?.image = image

        menu.removeAllItems()
        func line(_ title: String) { let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }
        func item(_ title: String, _ action: Selector) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }

        if guardian == nil {
            line("Lookout couldn't start its detector")
        } else if paused, let until = guardian?.state.pausedUntil {
            line("Lookout is paused until \(until.formatted(date: .omitted, time: .shortened))")
        } else {
            line(on ? "Lookout is on" : "Lookout is off")
        }
        if !Capture.allowed {
            item("Allow Screen Recording…", #selector(openScreenRecording))
        }
        if guardian != nil { item(on ? "Turn Off" : "Turn On", #selector(toggle)) }

        menu.addItem(.separator())
        if blockingBusy {
            line("Website blocking: working…")
        } else {
            switch Blocking.status {
            case .notSetUp:
                line("Website blocking: not set up")
                item("Set Up Website Blocking…", #selector(setUpBlocking))
            case .on:
                line("Website blocking: on")
                item("Turn Website Blocking Off…", #selector(blockingOff))
                item("Remove Website Blocking…", #selector(removeBlocking))
            case .off:
                line("Website blocking: off")
                item("Turn Website Blocking On…", #selector(blockingOn))
                item("Remove Website Blocking…", #selector(removeBlocking))
            }
        }
        menu.addItem(.separator())
        item("Open Log", #selector(openLog))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        line("Lookout \(version) · nothing leaves this Mac")
    }

    @objc func toggle() { guardian?.toggle() }

    @objc func openLog() {
        try? FileManager.default.createDirectory(at: Self.support, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.support)
    }

    @objc func openScreenRecording() {
        Capture.ask()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc func setUpBlocking() {
        confirm("Set up website blocking?",
                "Lookout will install AdGuard Home, a free DNS filter, download public adult block lists, "
                + "and point this Mac's DNS at it. It takes a minute or two and asks for your password once. "
                + "If lookups fail, it switches back by itself.") { self.runBlocking("install", "website blocking set up") }
    }
    @objc func blockingOff() { runBlocking("off", "website blocking turned off") }
    @objc func blockingOn() { runBlocking("on", "website blocking turned on") }
    @objc func removeBlocking() {
        confirm("Remove website blocking?", "This switches DNS back to your network's own servers and removes AdGuard Home.") {
            self.runBlocking("uninstall", "website blocking removed")
        }
    }

    private func confirm(_ title: String, _ text: String, then: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "Continue")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { then() }
    }

    private func runBlocking(_ command: String, _ done: String) {
        blockingBusy = true
        rebuildMenu()
        Task {
            let (ok, output) = await Blocking.run(command)
            blockingBusy = false
            if ok { log.append(Event(verdict: "blocking", action: done)) }
            rebuildMenu()
            if output.contains("User canceled") || output.contains("(-128)") { return }
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = ok ? "Done" : "That didn't work"
            a.informativeText = output.split(separator: "\n").suffix(12).joined(separator: "\n")
            a.runModal()
        }
    }
}
