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

/// Changes to editable transcript rows, expressed against the text the person saw.
/// A nil baseline identifies a new, text-only row. Hosts commit the batch atomically.
public struct VoicePanelEdit: Equatable, Sendable {
    public let id: UUID
    public let before: String?
    public let after: String

    public init(id: UUID, before: String?, after: String) {
        self.id = id
        self.before = before
        self.after = after
    }
}

extension PanelTimelineDocument {
    struct Edit {
        let rows: [VoicePanelEdit]
        let anchor: UUID
        let offset: Int
    }

    /// Time labels and inter-row separators are presentation. Removing a separator
    /// joins its neighbours while retaining both recording identities and audio.
    func edit(in range: NSRange, replacement: String, newRow: Bool) -> Edit? {
        let length = text.utf16.count
        guard range.location <= length, range.length <= length - range.location else { return nil }
        if spans.isEmpty || (newRow && range.location == length && range.length == 0) {
            guard !replacement.isEmpty else { return nil }
            let id = UUID()
            return Edit(rows: [.init(id: id, before: nil, after: replacement)],
                        anchor: id, offset: replacement.utf16.count)
        }
        // At a separator the left endpoint belongs to the preceding row;
        // the right endpoint belongs to the next row if the separator was removed.
        let firstIndex = spans.lastIndex { $0.range.location <= range.location } ?? 0
        let first = spans[firstIndex]
        let end = NSMaxRange(range)
        let lastIndex = range.length == 0 ? firstIndex :
            (spans.lastIndex { $0.range.location <= end } ?? firstIndex)
        let last = spans[lastIndex]
        let firstText = first.entry.displayText as NSString, lastText = last.entry.displayText as NSString
        let prefixLength = max(0, min(firstText.length, range.location - first.range.location))
        let suffixStart = max(0, min(lastText.length, end - last.range.location))
        let prefix = firstText.substring(to: prefixLength)
        let suffix = lastText.substring(from: suffixStart)
        let fragments = replacement.components(separatedBy: "\n")
        let rowCount = lastIndex - firstIndex + 1
        var values = Array(repeating: "", count: rowCount)
        // Keep the untouched tail in its original recording whenever the edit
        // leaves a line break between the two fragments.
        let canSplit = fragments.count > 1 && !fragments.contains("") &&
            !prefix.hasSuffix("\n") && !suffix.hasPrefix("\n")
        let tailRow = canSplit ? rowCount - 1 : 0
        if tailRow == 0 {
            values[0] = prefix + replacement + suffix
        } else {
            values[0] = prefix + fragments[0]
            let middle = min(rowCount - 2, fragments.count - 2)
            for index in 0..<middle { values[index + 1] = fragments[index + 1] }
            values[tailRow] = fragments.dropFirst(middle + 1).joined(separator: "\n") + suffix
        }
        let rows = zip(spans[firstIndex...lastIndex], values).compactMap { span, value in
            span.entry.displayText.utf16.elementsEqual(value.utf16) ? nil :
                VoicePanelEdit(id: span.entry.id, before: span.entry.displayText, after: value)
        }
        return Edit(rows: rows, anchor: spans[firstIndex + tailRow].entry.id,
                    offset: values[tailRow].utf16.count - suffix.utf16.count)
    }
}
