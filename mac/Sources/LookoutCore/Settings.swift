import Foundation

/// What Lookout checks for and how it reacts. Every value has a default; a
/// `settings.json` in Lookout's support folder can override any of them.
public struct Settings: Codable, Equatable {
    /// Seconds between looks. Kept light: about 2% of one core.
    public var intervalSeconds = 1.0
    /// Explicit nudity: one frame is enough.
    public var exposedClasses = ["FEMALE_BREAST_EXPOSED", "FEMALE_GENITALIA_EXPOSED",
                                 "MALE_GENITALIA_EXPOSED", "BUTTOCKS_EXPOSED", "ANUS_EXPOSED"]
    public var exposedThreshold: Float = 0.40
    /// Revealing: lingerie, swimsuits, suggestive poses. Needs several frames
    /// in a row so a single misread doesn't close a tab.
    public var revealingClasses = ["FEMALE_BREAST_COVERED", "FEMALE_GENITALIA_COVERED",
                                   "BUTTOCKS_COVERED", "ANUS_COVERED", "BELLY_EXPOSED"]
    public var revealingThreshold: Float = 0.55
    public var revealingFramesNeeded = 2
    /// How long the cover stays up if nobody presses a button.
    public var coverSeconds = 3.0
    /// Close the browser tab (or hide the app) after a flag. Off: cover only.
    public var closeTab = true
    /// "Wrong flag" on the cover pauses checking this long. Each pause is logged.
    public var pauseMinutes = 10.0
    /// Not checked while in front. Apps by bundle ID; pages by address start,
    /// matched in memory and never logged.
    public var skipApps = ["com.microsoft.Word"]
    public var skipPages = ["docs.google.com/spreadsheets"]
    /// Pages to leave for another, even when a site opens them without a new
    /// load: "linkedin.com/feed" -> "https://www.linkedin.com/messaging/".
    /// Chrome-like browsers and Safari. Off by default.
    public var redirectPages: [String: String] = [:]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case intervalSeconds = "interval_seconds", exposedClasses = "exposed_classes",
             exposedThreshold = "exposed_threshold", revealingClasses = "revealing_classes",
             revealingThreshold = "revealing_threshold", revealingFramesNeeded = "revealing_frames_needed",
             coverSeconds = "cover_seconds", closeTab = "close_tab", pauseMinutes = "pause_minutes",
             skipApps = "skip_apps", skipPages = "skip_pages", redirectPages = "redirect_pages"
    }

    /// Any key left out of the file keeps its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        intervalSeconds = try c.decodeIfPresent(Double.self, forKey: .intervalSeconds) ?? d.intervalSeconds
        exposedClasses = try c.decodeIfPresent([String].self, forKey: .exposedClasses) ?? d.exposedClasses
        exposedThreshold = try c.decodeIfPresent(Float.self, forKey: .exposedThreshold) ?? d.exposedThreshold
        revealingClasses = try c.decodeIfPresent([String].self, forKey: .revealingClasses) ?? d.revealingClasses
        revealingThreshold = try c.decodeIfPresent(Float.self, forKey: .revealingThreshold) ?? d.revealingThreshold
        revealingFramesNeeded = try c.decodeIfPresent(Int.self, forKey: .revealingFramesNeeded) ?? d.revealingFramesNeeded
        coverSeconds = try c.decodeIfPresent(Double.self, forKey: .coverSeconds) ?? d.coverSeconds
        closeTab = try c.decodeIfPresent(Bool.self, forKey: .closeTab) ?? d.closeTab
        pauseMinutes = try c.decodeIfPresent(Double.self, forKey: .pauseMinutes) ?? d.pauseMinutes
        skipApps = try c.decodeIfPresent([String].self, forKey: .skipApps) ?? d.skipApps
        skipPages = try c.decodeIfPresent([String].self, forKey: .skipPages) ?? d.skipPages
        redirectPages = try c.decodeIfPresent([String: String].self, forKey: .redirectPages) ?? d.redirectPages
    }

    /// Defaults, overridden by `file` when it exists. A broken file is
    /// ignored rather than stopping the guard.
    public static func load(from file: URL) -> Settings {
        guard let data = try? Data(contentsOf: file) else { return Settings() }
        return (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
    }
}
