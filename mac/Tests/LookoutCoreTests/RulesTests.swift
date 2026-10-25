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
