import AppKit
import Combine

/// Immutable transcript identity supplied by the host's own timeline.
public protocol VoiceTranscriptEntry: Equatable {
    var id: UUID { get }
    var position: Int64 { get }
    var displayText: String { get }
}

/// A bounded window of UTF-16 text. Hosts can supply time markers and grouped
/// snapshots, or construct a continuous document directly from their rows.
public struct PanelTimelineDocument<Entry: VoiceTranscriptEntry>: Equatable {
    public struct Span: Equatable {
        public let entry: Entry
        public let range: NSRange
        public init(entry: Entry, range: NSRange) { self.entry = entry; self.range = range }
    }
    public var text = ""
    public var spans: [Span] = []
    public var markers: [NSRange] = []
    public var displayed: [Int64: String] = [:]
    public var activeStart: Int?
    public var idle = false
    public var firstPosition: Int64?
    public var lastPosition: Int64?
    public var older = false
    public var newer = false

    public init() {}

    public init(entries: [Entry], older: Bool = false, newer: Bool = false) {
        self.older = older
        self.newer = newer
        firstPosition = entries.first?.position
        lastPosition = entries.last?.position
        let content = NSMutableString(capacity: 256)
        for entry in entries {
            displayed[entry.position] = entry.displayText
            guard !entry.displayText.isEmpty else { continue }
            if content.length > 0 { content.append("\n") }
            let start = content.length
            content.append(entry.displayText)
            spans.append(Span(entry: entry, range: NSRange(location: start, length: content.length - start)))
        }
        text = content as String
    }
}

@MainActor public final class PanelTranscriptAccess<Entry: VoiceTranscriptEntry>: ObservableObject {
    public internal(set) weak var view: CompactTranscriptScrollView<Entry>?
    public init() {}
}

/// Time grouping belongs to the recording's original civil day and offset.
public protocol GroupedVoiceTranscriptEntry: VoiceTranscriptEntry {
    var group: Int64 { get }
    var groupStart: Date { get }
    var groupDay: String { get }
    var groupUTCOffset: Int { get }
}

extension PanelTimelineDocument where Entry: GroupedVoiceTranscriptEntry {
    public init(entries: [Entry], tailGroup: Int64?, idle: Bool, reading: Bool, older: Bool = false, newer: Bool = false) {
        self.init()
        self.idle = idle && !newer
        // An empty utterance is also a rendered state. Its first ASR callback
        // may already be committed when the click reaches SQLite.
        displayed = Dictionary(uniqueKeysWithValues: entries.map { ($0.position, $0.displayText) })
        firstPosition = entries.first?.position
        lastPosition = entries.last?.position
        self.older = older
        self.newer = newer
        let content = NSMutableString(capacity: 256)
        var group: Int64?, day: String?
        for row in entries where !row.displayText.isEmpty {
            if content.length > 0 { content.append("\n") }
            if group != row.group {
                if !reading && row.group == tailGroup && content.length > 0 {
                    // Optical inset above live text must not expose the last glyphs of history.
                    content.append("\n")
                }
                if reading || row.group != tailGroup {
                    let start = content.length
                    let offset = Double(row.groupUTCOffset)
                    let second = (Int(floor(row.groupStart.timeIntervalSince1970 + offset)) % 86400 + 86400) % 86400
                    let time = String(format: "%02d:%02d", second / 3600, second / 60 % 60)
                    content.append((day != row.groupDay ? row.groupDay + "  " : "") + time)
                    markers.append(NSRange(location: start, length: content.length - start))
                    content.append("\n")
                }
                group = row.group
                day = row.groupDay
                if group == tailGroup { activeStart = content.length }
            }
            let start = content.length
            content.append(row.displayText)
            spans.append(Span(entry: row, range: NSRange(location: start, length: content.length - start)))
        }
        // A new utterance can arrive before the first recognition result.
        if activeStart == nil && !newer { activeStart = content.length }
        text = content as String
    }
}
