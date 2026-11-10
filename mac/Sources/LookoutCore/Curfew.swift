import Foundation

/// The nightly curfew: a screen from `start` to `end` that only the
/// working-late pass lifts, `passMinutes` at a time, with a notice
/// `warnMinutes` before. Times are local "HH:mm" and may wrap past midnight.
public struct Curfew: Codable, Equatable {
    public var start = "22:00"
    public var end = "07:00"
    public var warnMinutes = 15
    public var passMinutes = 30

    public init() {}

    enum CodingKeys: String, CodingKey {
        case start, end, warnMinutes = "warn_minutes", passMinutes = "pass_minutes"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Curfew()
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? d.start
        end = try c.decodeIfPresent(String.self, forKey: .end) ?? d.end
        warnMinutes = try c.decodeIfPresent(Int.self, forKey: .warnMinutes) ?? d.warnMinutes
        passMinutes = try c.decodeIfPresent(Int.self, forKey: .passMinutes) ?? d.passMinutes
    }

    public enum State: Equatable { case off, warn, night, pass }

    private static func minutes(_ hm: String) -> Int {
        let p = hm.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 0
    }

    public func isNight(at date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let t = (c.hour ?? 0) * 60 + (c.minute ?? 0), s = Self.minutes(start), e = Self.minutes(end)
        // Kept line for line with isNight in proofs/Lookout.lean. A start equal
        // to the end is an empty window (it used to mean start to midnight).
        return s < e ? (s <= t && t < e) : s > e ? (t >= s || t < e) : false
    }

    /// Where things stand at `date`, given when the last pass was taken.
    public func state(at date: Date, lastPass: Date?, calendar: Calendar = .current) -> State {
        if isNight(at: date, calendar: calendar) {
            if let lastPass, date >= lastPass, date.timeIntervalSince(lastPass) < Double(passMinutes) * 60 { return .pass }
            return .night
        }
        return isNight(at: date.addingTimeInterval(Double(warnMinutes) * 60), calendar: calendar) ? .warn : .off
    }
}

/// The last working-late pass, from the log, so a restart doesn't take one back.
public func lastCurfewPass(_ events: [Event]) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return events.last { $0.verdict == "curfew pass" }.flatMap { f.date(from: $0.time) }
}
