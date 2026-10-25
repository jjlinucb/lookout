import Foundation

/// A rectangle in pixels: x, y from the top left, then width and height.
public struct Box: Equatable, Codable {
    public var x, y, w, h: Int
    public init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { (self.x, self.y, self.w, self.h) = (x, y, w, h) }

    public func overlaps(_ b: Box) -> Bool {
        x < b.x + b.w && b.x < x + w && y < b.y + b.h && b.y < y + h
    }
}

/// One thing the detector found.
public struct Hit: Equatable {
    public var label: String
    public var score: Float
    public var box: Box
    public init(_ label: String, _ score: Float, _ box: Box = Box(0, 0, 1, 1)) {
        (self.label, self.score, self.box) = (label, score, box)
    }
}

public enum Verdict: String { case exposed, revealing }

/// Decides whether this look's hits count. Exposed counts at once; revealing
/// counts only after `revealingFramesNeeded` looks in a row.
public struct Judge {
    public var settings: Settings
    public private(set) var revealingStreak = 0

    public init(_ settings: Settings) { self.settings = settings }

    public mutating func reset() { revealingStreak = 0 }

    public mutating func judge(_ hits: [Hit]) -> (Verdict, [Hit])? {
        let exposed = hits.filter { settings.exposedClasses.contains($0.label) && $0.score >= settings.exposedThreshold }
        if !exposed.isEmpty {
            revealingStreak = 0
            return (.exposed, exposed)
        }
        let revealing = hits.filter { settings.revealingClasses.contains($0.label) && $0.score >= settings.revealingThreshold }
        guard !revealing.isEmpty else {
            revealingStreak = 0
            return nil
        }
        revealingStreak += 1
        guard revealingStreak >= settings.revealingFramesNeeded else { return nil }
        revealingStreak = 0
        return (.revealing, revealing)
    }
}

/// True while a skipped app or page is in front.
public func isSkipped(bundleID: String, url: String?, settings: Settings) -> Bool {
    if settings.skipApps.contains(bundleID) { return true }
    guard let url else { return false }
    let page = url.range(of: "://").map { String(url[$0.upperBound...]) } ?? url
    return settings.skipPages.contains { page.hasPrefix($0) }
}

/// The site's domain (chase.com), never the full address, which can carry
/// account numbers or session tokens.
public func domain(of url: String?) -> String? {
    guard let url, let host = URL(string: url)?.host?.lowercased(), !host.isEmpty else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}
