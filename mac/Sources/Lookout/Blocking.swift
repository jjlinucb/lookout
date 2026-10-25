import AppKit
import Foundation

/// Website blocking: AdGuard Home installed and switched by the bundled
/// `blocking/lookout-blocking.sh`, run with one administrator prompt.
enum Blocking {
    enum Status { case notSetUp, on, off }

    static var script: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("blocking/lookout-blocking.sh")
    }

    static var status: Status {
        guard FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/io.github.jjlinucb.lookout.adguardhome.plist")
        else { return .notSetUp }
        // The resolver configuration is world-readable; no admin needed to look.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        p.arguments = ["--dns"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return .off }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return out.contains("nameserver[0] : 127.0.0.1") ? .on : .off
    }

    /// Runs `lookout-blocking.sh <command>` as administrator. macOS asks for
    /// the password. Returns the script's output, or the error.
    static func run(_ command: String) async -> (ok: Bool, output: String) {
        guard let script else { return (false, "The blocking scripts are missing from the app.") }
        let source = """
            do shell script quoted form of "\(script.path)" & " \(command) 2>&1" \
            with prompt "Lookout needs your password to change website blocking." with administrator privileges
            """
        return await withCheckedContinuation { done in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", source]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do { try p.run() } catch { return done.resume(returning: (false, "\(error)")) }
                let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                p.waitUntilExit()
                done.resume(returning: (p.terminationStatus == 0, out.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
}
