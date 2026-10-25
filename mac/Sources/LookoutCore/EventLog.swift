import Foundation

/// One line in the local log. Callers pass a domain, never a full address.
public struct Event: Codable, Equatable {
    public var time: String
    public var verdict: String
    public var app: String
    public var domain: String?
    public var action: String
    public var hits: [Scored]

    public struct Scored: Codable, Equatable {
        public var `class`: String
        public var score: Float
    }

    public init(verdict: String, app: String = "", domain: String? = nil, action: String, hits: [Hit] = [],
                at date: Date = Date()) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        time = f.string(from: date)
        (self.verdict, self.app, self.domain, self.action) = (verdict, app, domain, action)
        self.hits = hits.map { Scored(class: $0.label, score: ($0.score * 100).rounded() / 100) }
    }
}

/// The log lives only on this Mac: `events.jsonl`, one event per line, plus
/// `flagged-domains.txt` listing the sites that were flagged.
public struct EventLog {
    public let folder: URL
    public var events: URL { folder.appendingPathComponent("events.jsonl") }
    public var flagged: URL { folder.appendingPathComponent("flagged-domains.txt") }

    public init(folder: URL) { self.folder = folder }

    public func append(_ e: Event) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        guard var line = try? enc.encode(e) else { return }
        line.append(0x0A)
        Self.appendData(line, to: events)
        if let d = e.domain, Verdict(rawValue: e.verdict) != nil {
            Self.appendData(Data((d + "\n").utf8), to: flagged)
        }
    }

    public func read() -> [Event] {
        guard let text = try? String(contentsOf: events, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(Event.self, from: Data($0.utf8)) }
    }

    static func appendData(_ data: Data, to url: URL) {
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
