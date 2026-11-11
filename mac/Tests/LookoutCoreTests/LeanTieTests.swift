import Foundation
import Testing
@testable import LookoutCore

/// Ties the Swift code to the Lean model in proofs/Lookout.lean. Lean proves
/// its promises about the model; `check.sh` has the model print its answers
/// to lean-vectors.txt, and this test asks the Swift code the same questions.
/// Any difference means the proofs no longer describe the app.
@Suite struct LeanTieTests {
    let lines: [[String]] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("lean-vectors.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
    }()

    var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func hm(_ m: String) -> String { String(format: "%02d:%02d", Int(m)! / 60, Int(m)! % 60) }

    func curfew(_ f: [String]) -> Curfew {
        var c = Curfew()
        c.start = hm(f[1]); c.end = hm(f[2])
        if f.count > 6 { c.warnMinutes = Int(f[3])!; c.passMinutes = Int(f[4])! }
        return c
    }

    func date(_ seconds: String) -> Date { Date(timeIntervalSince1970: Double(Int(seconds)!)) }

    @Test func vectorsArePresent() {
        for kind in ["night", "state", "redirect", "guard", "close"] {
            #expect(lines.filter { $0.first == kind }.count > 100, "no \(kind) vectors; run ./check.sh")
        }
    }

    @Test func curfewHoursMatchTheModel() {
        for f in lines where f.first == "night" {
            let got = curfew(f).isNight(at: date(String(Int(f[3])! * 60)), calendar: utc)
            #expect(String(got) == f[4], "\(f)")
        }
    }

    @Test func curfewStateMatchesTheModel() {
        for f in lines where f.first == "state" {
            let lastPass = f[6] == "-" ? nil : date(f[6])
            let got = curfew(f).state(at: date(f[5]), lastPass: lastPass, calendar: utc)
            #expect("\(got)" == f[7], "\(f)")
        }
    }

    @Test func redirectsMatchTheModel() {
        for f in lines where f.first == "redirect" {
            var s = Settings()
            s.redirectPages = [f[1]: "https://example.org/"]
            let url = "https://\(f[2])\(f[3] == "-" ? "" : f[3])"
            #expect(String(redirect(for: url, settings: s) != nil) == f[4], "\(f)")
        }
    }

    @Test func pausesMatchTheModel() {
        let log = EventLog(folder: FileManager.default.temporaryDirectory.appendingPathComponent("lookout-lean-\(UUID().uuidString)"))
        var states: [String: GuardState] = [:]
        for f in lines where f.first == "guard" {
            let key = f[1] + " " + f[2]
            if states[key] == nil {
                var g = GuardState(log: log, pauseMinutes: Double(f[1])!)
                for a in f[2] == "-" ? [] : f[2].split(separator: ",").map(String.init) {
                    if a == "T" { g.toggle() }
                    else if a.hasPrefix("W") { g.pause(at: date(String(a.dropFirst()))) }
                    else {
                        let p = a.dropFirst().split(separator: "x").map(String.init)
                        g.pauseFromMenu(minutes: Double(p[1])!, at: date(p[0]))
                    }
                }
                states[key] = g
            }
            #expect(String(states[key]!.shouldCheck(at: date(f[3]))) == f[4], "\(f)")
        }
    }

    @Test func closingMatchesTheModel() {
        for f in lines where f.first == "close" {
            var s = Settings()
            s.closeTab = f[1] == "true"
            s.closeRevealingAt = Float(Int(f[2])!) / 1000
            let hits = f[4] == "-" ? [] : f[4].split(separator: ",").map { Hit("x", Float(Int($0)!) / 1000) }
            let got = shouldClose(Verdict(rawValue: f[3])!, hits, settings: s)
            #expect(String(got) == f[5], "\(f)")
        }
    }
}
