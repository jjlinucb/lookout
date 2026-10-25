import Foundation
import Testing
@testable import LookoutCore

func tempLog() -> EventLog {
    EventLog(folder: FileManager.default.temporaryDirectory.appendingPathComponent("lookout-test-\(UUID().uuidString)"))
}

@Suite struct PrivacyTests {
    @Test func domainOnly() {
        #expect(domain(of: "https://www.chase.com/acct/123456?token=abc") == "chase.com")
        #expect(domain(of: nil) == nil)
        #expect(domain(of: "not a url") == nil)
    }

    @Test func logHoldsNoAddress() throws {
        let log = tempLog()
        log.append(Event(verdict: "exposed", app: "Chrome", domain: domain(of: "https://bad.example/x?id=42"),
                         action: "closed tab", hits: [Hit("FEMALE_BREAST_EXPOSED", 0.8712)]))
        let raw = try String(contentsOf: log.events, encoding: .utf8)
        #expect(!raw.contains("id=42"))
        #expect(try String(contentsOf: log.flagged, encoding: .utf8) == "bad.example\n")
        #expect(log.read().first?.hits.first?.score == 0.87)
    }

    @Test func onlyFlagsGoInTheFlaggedList() {
        let log = tempLog()
        log.append(Event(verdict: "paused", domain: "example.com", action: "wrong flag"))
        #expect(!FileManager.default.fileExists(atPath: log.flagged.path))
    }
}

@Suite struct GuardStateTests {
    @Test func turningOffAndOnIsLogged() {
        let log = tempLog()
        var g = GuardState(log: log, pauseMinutes: 10)
        g.toggle()
        #expect(!g.on && !g.shouldCheck())
        g.toggle()
        #expect(g.on && g.shouldCheck())
        #expect(log.read().map(\.verdict) == ["turned off", "turned on"])
    }

    @Test func wrongFlagPausesTenMinutesAndIsLogged() {
        let log = tempLog()
        var g = GuardState(log: log, pauseMinutes: 10)
        let now = Date()
        g.pause(at: now)
        #expect(!g.shouldCheck(at: now.addingTimeInterval(9 * 60)))
        #expect(g.shouldCheck(at: now.addingTimeInterval(10 * 60 + 1)))
        #expect(log.read().map(\.verdict) == ["paused"])
    }
}
