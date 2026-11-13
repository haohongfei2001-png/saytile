import AppKit
import Combine

/// Immutable transcript identity supplied by the host's own timeline.
public protocol VoiceTranscriptEntry: Equatable {
    var id: UUID { get }
    var position: Int64 { get }
    var displayText: String { get }
}

/// A bounded slice of the editable transcript. Recording identities and time
/// groups are metadata and never add lines to the text.
public struct PanelTimelineDocument<Entry: VoiceTranscriptEntry>: Equatable {
    public struct Span: Equatable {
        public let entry: Entry
        public let range: NSRange
        public init(entry: Entry, range: NSRange) { self.entry = entry; self.range = range }
    }
    public var text = ""
    /// Only the recording's current ASR partial may be revealed over multiple frames.
    public var liveTailID: UUID?
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
        var preceding: String?
        for entry in entries {
            displayed[entry.position] = entry.displayText
            guard !entry.displayText.isEmpty else { continue }
            if let preceding { content.append(VoiceTranscriptFlow.separator(between: preceding, and: entry.displayText)) }
            preceding = entry.displayText
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
    public init(entries: [Entry], tailGroup: Int64?, idle: Bool, reading _: Bool, older: Bool = false, newer: Bool = false) {
        self.init(entries: entries, older: older, newer: newer)
        self.idle = idle && !newer
        activeStart = spans.first { $0.entry.group == tailGroup }?.range.location
        if activeStart == nil && !newer { activeStart = text.utf16.count }
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

    /// Apply an AppKit UTF-16 replacement to its original recording rows.
    func edit(in range: NSRange, replacement: String, newRow: Bool) -> Edit? {
        let length = text.utf16.count
        guard range.location >= 0, range.location <= length, range.length >= 0, range.length <= length - range.location else { return nil }
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
        // Only the two outside neighbours can gain or lose an automatic word
        // space. Keep their original gaps even when the adjacent text changes
        // script, or when the entire word between them is removed.
        let lower = max(0, firstIndex - 1), upper = min(spans.count - 1, lastIndex + 1)
        let local = Array(spans[lower...upper])
        let firstLocal = firstIndex - lower, lastLocal = lastIndex - lower
        var pieces = local.map { $0.entry.displayText }
        for index in firstLocal...lastLocal { pieces[index] = "" }
        pieces[firstLocal] = prefix + replacement
        pieces[lastLocal] += suffix

        var values = Array(repeating: "", count: pieces.count)
        var preceding: Int?
        var gap = ""
        for (index, piece) in pieces.enumerated() {
            if index > 0 && (index <= firstLocal || index > lastLocal),
               local[index].range.location > NSMaxRange(local[index - 1].range) {
                gap += " "
            }
            guard !piece.isEmpty else { continue }
            if let prior = preceding {
                let natural = VoiceTranscriptFlow.separator(between: values[prior], and: piece)
                if gap == natural {
                    values[index] = piece
                } else if gap.isEmpty {
                    // The edit intentionally joined two Latin words. Keeping
                    // separate rendered words here would reinsert the space.
                    values[prior] += piece
                    continue
                } else if index > lastLocal {
                    values[prior] += gap
                    values[index] = piece
                } else {
                    values[index] = gap + piece
                }
            } else {
                values[index] = gap + piece
            }
            gap = ""
            preceding = index
        }
        if !gap.isEmpty { values[lastLocal] += gap }

        let rows = zip(local, values).compactMap { span, value in
            span.entry.displayText.utf16.elementsEqual(value.utf16) ? nil :
                VoicePanelEdit(id: span.entry.id, before: span.entry.displayText, after: value)
        }
        let caret = range.location + replacement.utf16.count
        var cursor = local[0].range.location
        var previous = ""
        for (index, value) in values.enumerated() {
            if !value.isEmpty { cursor += VoiceTranscriptFlow.separator(between: previous, and: value).utf16.count }
            let end = cursor + value.utf16.count
            if index >= firstLocal && (cursor...end).contains(caret) {
                return Edit(rows: rows, anchor: local[index].entry.id, offset: caret - cursor)
            }
            if !value.isEmpty { previous = value }
            cursor = end
        }
        // Joining an automatic space can move the caret into the previous row.
        return Edit(rows: rows, anchor: local[0].entry.id, offset: caret - local[0].range.location)
    }
}
