import AppKit
import Foundation

/// The app in front, the active tab's address, and closing that tab.
/// Addresses are read only to match the skip list and to log the domain.
enum Browser {
    static let chromium: Set = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser",
                                "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]
    static let safari: Set = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static let firefox: Set = ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "app.zen-browser.zen"]

    static let scripts = ScriptRunner()

    static func isBrowser(_ id: String) -> Bool { chromium.contains(id) || safari.contains(id) || firefox.contains(id) }

    /// The active tab's address in Chrome-like browsers and Safari; nil elsewhere.
    static func url(of id: String) -> String? {
        if chromium.contains(id) {
            return scripts.run("tell application id \"\(id)\" to get URL of active tab of front window")
        }
        if safari.contains(id) {
            return scripts.run("tell application id \"\(id)\" to get URL of current tab of front window")
        }
        return nil
    }

    /// Close the offending tab; for anything that isn't a browser, hide the app.
    static func close(_ app: NSRunningApplication) -> String {
        let id = app.bundleIdentifier ?? ""
        var ok = false
        if chromium.contains(id) {
            ok = scripts.run("tell application id \"\(id)\" to close active tab of front window") != nil
        } else if safari.contains(id) {
            ok = scripts.run("tell application id \"\(id)\" to close current tab of front window") != nil
        } else if firefox.contains(id) {
            // Firefox has no AppleScript tabs; Cmd-W needs Accessibility permission.
            ok = scripts.run("tell application \"System Events\" to keystroke \"w\" using command down") != nil
        }
        if ok { return "closed tab" }
        return app.hide() ? "hid app" : "no action"
    }
}

/// Runs AppleScript in this process, on one thread of its own, so a pending
/// "Lookout wants to control Chrome" prompt never freezes the menu bar or
/// the guard. Every call gives up after a few seconds.
final class ScriptRunner: NSObject {
    private final class Job: NSObject {
        let source: String
        let done = DispatchSemaphore(value: 0)
        var result: String?
        init(_ source: String) { self.source = source }
    }

    private var thread: Thread!
    private var compiled: [String: NSAppleScript] = [:]

    override init() {
        super.init()
        thread = Thread {
            RunLoop.current.add(Port(), forMode: .default)
            RunLoop.current.run()
        }
        thread.name = "Lookout AppleScript"
        thread.start()
    }

    func run(_ source: String, timeout: Double = 5) -> String? {
        let job = Job(source)
        perform(#selector(execute(_:)), on: thread, with: job, waitUntilDone: false)
        return job.done.wait(timeout: .now() + timeout) == .success ? job.result : nil
    }

    @objc private func execute(_ job: Job) {
        defer { job.done.signal() }
        if compiled[job.source] == nil { compiled[job.source] = NSAppleScript(source: job.source) }
        var error: NSDictionary?
        let out = compiled[job.source]?.executeAndReturnError(&error)
        job.result = error == nil ? (out?.stringValue ?? "") : nil
    }
}
