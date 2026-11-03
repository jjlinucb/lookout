import Foundation
import Testing
@testable import LookoutCore

@Suite struct JudgeTests {
    var j = Judge(Settings())

    @Test mutating func exposedBlocksOnOneFrame() {
        #expect(j.judge([Hit("FEMALE_BREAST_EXPOSED", 0.5)])?.0 == .exposed)
    }

    @Test mutating func belowThresholdPasses() {
        #expect(j.judge([Hit("FEMALE_BREAST_EXPOSED", 0.3)]) == nil)
    }

    @Test mutating func revealingNeedsTwoFramesInARow() {
        let r = [Hit("BUTTOCKS_COVERED", 0.7)]
        #expect(j.judge(r) == nil)
        #expect(j.judge(r)?.0 == .revealing)
    }

    @Test mutating func cleanFrameResetsTheStreak() {
        let r = [Hit("BUTTOCKS_COVERED", 0.7)]
        _ = j.judge(r)
        _ = j.judge([])
        #expect(j.judge(r) == nil)
    }

    @Test mutating func facesAndFeetNeverCount() {
        #expect(j.judge([Hit("FACE_FEMALE", 0.99), Hit("FEET_EXPOSED", 0.99)]) == nil)
    }
}

@Suite struct SkipTests {
    let s = Settings()

    @Test func wordIsSkipped() {
        #expect(isSkipped(bundleID: "com.microsoft.Word", url: nil, settings: s))
    }

    @Test func googleSheetsIsSkipped() {
        #expect(isSkipped(bundleID: "com.google.Chrome", url: "https://docs.google.com/spreadsheets/d/abc/edit", settings: s))
    }

    @Test func otherGoogleDocsAndSitesAreChecked() {
        #expect(!isSkipped(bundleID: "com.google.Chrome", url: "https://docs.google.com/document/d/abc", settings: s))
        #expect(!isSkipped(bundleID: "com.google.Chrome", url: "https://badsite.example/docs.google.com/spreadsheets", settings: s))
    }
}

@Suite struct RedirectTests {
    var s: Settings {
        var s = Settings()
        s.redirectPages = ["linkedin.com/feed": "https://www.linkedin.com/messaging/"]
        return s
    }

    @Test func feedGoesToMessaging() {
        for url in ["https://www.linkedin.com/feed/", "https://linkedin.com/feed", "https://www.linkedin.com/feed/foryou/?x=1"] {
            #expect(redirect(for: url, settings: s) == "https://www.linkedin.com/messaging/")
        }
    }

    @Test func restOfTheSiteAndLookalikesStayPut() {
        for url in ["https://www.linkedin.com/messaging/", "https://www.linkedin.com/mynetwork/",
                    "https://www.linkedin.com/feedback", "https://notlinkedin.com/feed",
                    "https://badsite.example/linkedin.com/feed", "https://linkedin.com.evil.example/feed"] {
            #expect(redirect(for: url, settings: s) == nil)
        }
    }

    @Test func offByDefault() {
        #expect(redirect(for: "https://www.linkedin.com/feed/", settings: Settings()) == nil)
    }
}

@Suite struct CloseByKindTests {
    @Test func exposedAlwaysCloses() {
        #expect(shouldClose(.exposed, [Hit("FEMALE_BREAST_EXPOSED", 0.41)], settings: Settings()))
    }

    @Test func revealingClosesOnlyWhenStrong() {
        #expect(!shouldClose(.revealing, [Hit("BUTTOCKS_COVERED", 0.6)], settings: Settings()))
        #expect(shouldClose(.revealing, [Hit("BUTTOCKS_COVERED", 0.5), Hit("BELLY_EXPOSED", 0.7)], settings: Settings()))
    }

    @Test func closeTabOffNeverCloses() {
        var s = Settings()
        s.closeTab = false
        #expect(!shouldClose(.exposed, [Hit("FEMALE_BREAST_EXPOSED", 0.9)], settings: s))
    }

    @Test func nightCountsRevealingOnTheFirstFrame() {
        var j = Judge(Settings())
        #expect(j.judge([Hit("BUTTOCKS_COVERED", 0.7)], night: true)?.0 == .revealing)
    }
}

@Suite struct CurfewTests {
    let c = Curfew()
    var cal: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }
    func at(_ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: h, minute: m))! }

    @Test func hoursWrapPastMidnight() {
        #expect(c.state(at: at(21, 0), lastPass: nil, calendar: cal) == .off)
        #expect(c.state(at: at(21, 50), lastPass: nil, calendar: cal) == .warn)
        #expect(c.state(at: at(22, 0), lastPass: nil, calendar: cal) == .night)
        #expect(c.state(at: at(3, 0), lastPass: nil, calendar: cal) == .night)
        #expect(c.state(at: at(7, 0), lastPass: nil, calendar: cal) == .off)
    }

    @Test func passLiftsItThirtyMinutes() {
        #expect(c.state(at: at(23, 20), lastPass: at(23, 0), calendar: cal) == .pass)
        #expect(c.state(at: at(23, 31), lastPass: at(23, 0), calendar: cal) == .night)
    }

    @Test func offUnlessSetAndReadFromJSON() throws {
        #expect(Settings().curfew == nil)
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"curfew": {"start": "23:00"}}"#.utf8))
        #expect(s.curfew?.start == "23:00")
        #expect(s.curfew?.passMinutes == 30)
    }
}

@Suite struct SettingsTests {
    @Test func missingKeysKeepDefaults() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"pause_minutes": 5, "skip_apps": []}"#.utf8))
        #expect(s.pauseMinutes == 5)
        #expect(s.skipApps.isEmpty)
        #expect(s.exposedThreshold == 0.40)
        #expect(s.intervalSeconds == 1.0)
    }

    @Test func brokenFileFallsBackToDefaults() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("not json".utf8).write(to: f)
        #expect(Settings.load(from: f) == Settings())
    }
}
