import Foundation

/// On, off and paused, with every switch written to the log.
public struct GuardState {
    public private(set) var on = true
    public private(set) var pausedUntil = Date.distantPast
    let log: EventLog
    let pauseMinutes: Double

    public init(log: EventLog, pauseMinutes: Double) { (self.log, self.pauseMinutes) = (log, pauseMinutes) }

    public func shouldCheck(at now: Date = Date()) -> Bool { on && now >= pausedUntil }

    /// The menu bar's Turn Off / Turn On.
    public mutating func toggle() {
        on.toggle()
        log.append(Event(verdict: on ? "turned on" : "turned off", action: "menu bar"))
    }

    /// The cover's "Wrong flag" button: stop checking for a while, on the record.
    public mutating func pause(at now: Date = Date()) {
        pausedUntil = now.addingTimeInterval(pauseMinutes * 60)
        log.append(Event(verdict: "paused", action: "wrong flag: paused \(Int(pauseMinutes)) min"))
    }
}
