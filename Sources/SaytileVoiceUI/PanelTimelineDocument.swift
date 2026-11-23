import AppKit
import Combine

/// Immutable transcript identity supplied by the host's own timeline.
public protocol VoiceTranscriptEntry: Equatable {
    var id: UUID { get }
    var position: Int64 { get }
    var displayText: String { get }
    /// Stable identity of the natural paragraph, independent of ASR revisions.
    var paragraphID: Int64 { get }
    /// Explicit paragraph-boundary override, shared by all original rows in a paragraph.
    var paragraphBreakHidden: Bool { get }
}

public extension VoiceTranscriptEntry {
    // Hosts without paragraph metadata retain the original continuous text flow.
    var paragraphID: Int64 { 0 }
    var paragraphBreakHidden: Bool { false }
}

/// A bounded slice of the editable transcript. Recording identities and time
/// groups never add lines. Only a host-supplied natural paragraph may add a break.
public struct PanelTimelineDocument<Entry: VoiceTranscriptEntry>: Equatable {
    public struct Span: Equatable {
        public let entry: Entry
        public let range: NSRange
        public init(entry: Entry, range: NSRange) { self.entry = entry; self.range = range }
    }
    public private(set) var entries: [Entry] = []
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
        self.entries = entries
        for entry in entries { displayed[entry.position] = entry.displayText }
        let rendered = Self.render(entries)
        text = rendered.text
        spans = rendered.spans
    }

    private static func render(_ entries: [Entry], replacing: [UUID: String] = [:],
                               hiddenBreaks: [Int64: Bool] = [:]) -> (text: String, spans: [Span]) {
        let content = NSMutableString(capacity: 256)
        var spans: [Span] = []
        var preceding: String?
        var paragraph: Int64?
        var pendingBreak = false
        for entry in entries {
            let text = replacing[entry.id] ?? entry.displayText
            let hidden = hiddenBreaks[entry.paragraphID] ?? entry.paragraphBreakHidden
            if let paragraph, paragraph != entry.paragraphID { pendingBreak = !hidden }
            else if hidden { pendingBreak = false }
            paragraph = entry.paragraphID
            // Empty ASR rows retain their stable paragraph identity. Only an
            // explicit boundary override suppresses a later paragraph break.
            guard !text.isEmpty else { continue }
            if let preceding {
                if pendingBreak && !endsInNewline(preceding) && !startsWithNewline(text) {
                    content.append("\n")
                } else { content.append(VoiceTranscriptFlow.separator(between: preceding, and: text)) }
            }
            preceding = text
            pendingBreak = false
            let start = content.length
            content.append(text)
            spans.append(Span(entry: entry, range: NSRange(location: start, length: content.length - start)))
        }
        return (content as String, spans)
    }

    private static func startsWithNewline(_ text: String) -> Bool {
        text.unicodeScalars.first.map(CharacterSet.newlines.contains) ?? false
    }
    private static func endsInNewline(_ text: String) -> Bool {
        text.unicodeScalars.last.map(CharacterSet.newlines.contains) ?? false
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
    public let paragraphBreakHidden: Bool?
    public let previousParagraphBreakHidden: Bool?

    public init(id: UUID, before: String?, after: String, paragraphBreakHidden: Bool? = nil,
                previousParagraphBreakHidden: Bool? = nil) {
        self.id = id
        self.before = before
        self.after = after
        self.paragraphBreakHidden = paragraphBreakHidden
        self.previousParagraphBreakHidden = previousParagraphBreakHidden
    }
}

extension PanelTimelineDocument {
    /// Shared by the live board and archive editors; no host reimplements range mapping.
    public func edits(for range: NSRange, replacement: String) -> [VoicePanelEdit]? {
        edit(in: range, replacement: replacement, newRow: false)?.rows
    }

    /// Map an editor's complete snapshot through one exact, scalar-safe UTF-16 patch.
    public func edits(replacingDisplayedText replacement: String) -> [VoicePanelEdit]? {
        guard !text.utf16.elementsEqual(replacement.utf16) else { return [] }
        if spans.isEmpty, let first = entries.first {
            return [.init(id: first.id, before: first.displayText, after: replacement)]
        }
        let old = Array(text.unicodeScalars), new = Array(replacement.unicodeScalars)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        let location = old[..<prefix].reduce(0) { $0 + $1.utf16.count }
        let length = old[prefix..<(old.count - suffix)].reduce(0) { $0 + $1.utf16.count }
        let inserted = String(String.UnicodeScalarView(new[prefix..<(new.count - suffix)]))
        return edits(for: NSRange(location: location, length: length), replacement: inserted)
    }

    private func separator(after prior: Entry, before next: Entry, left: String, right: String,
                           replacing: [UUID: String], hiddenBreaks: [Int64: Bool]) -> String {
        guard let start = entries.firstIndex(where: { $0.id == prior.id }),
              let end = entries.firstIndex(where: { $0.id == next.id }), end > start else {
            return VoiceTranscriptFlow.separator(between: left, and: right)
        }
        var paragraph = prior.paragraphID, pendingBreak = false
        for entry in entries[(start + 1)...end] {
            let value = replacing[entry.id] ?? entry.displayText
            let hidden = hiddenBreaks[entry.paragraphID] ?? entry.paragraphBreakHidden
            if paragraph != entry.paragraphID { pendingBreak = !hidden }
            else if hidden { pendingBreak = false }
            paragraph = entry.paragraphID
            if entry.id != next.id, !value.isEmpty { pendingBreak = false }
        }
        if pendingBreak && !Self.endsInNewline(left) && !Self.startsWithNewline(right) { return "\n" }
        return VoiceTranscriptFlow.separator(between: left, and: right)
    }

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
        var hiddenBreaks: [Int64: Bool] = [:]
        var preceding: Int?
        var gap = ""
        for (index, piece) in pieces.enumerated() {
            if index > 0 && (index <= firstLocal || index > lastLocal),
               local[index].range.location > NSMaxRange(local[index - 1].range) {
                let previousEnd = NSMaxRange(local[index - 1].range)
                gap += (text as NSString).substring(with: NSRange(location: previousEnd,
                    length: local[index].range.location - previousEnd))
            }
            guard !piece.isEmpty else { continue }
            if let prior = preceding {
                var replacements = Dictionary(uniqueKeysWithValues: zip(local, values).map { ($0.entry.id, $1) })
                replacements[local[index].entry.id] = piece
                var natural = separator(after: local[prior].entry, before: local[index].entry,
                                        left: values[prior], right: piece, replacing: replacements, hiddenBreaks: hiddenBreaks)
                if natural == "\n", !gap.contains("\n") {
                    // Preserve an explicit join as metadata, never infer it from
                    // a blank transcript or an unrelated archive edit.
                    hiddenBreaks[local[index].entry.paragraphID] = true
                    natural = VoiceTranscriptFlow.separator(between: values[prior], and: piece)
                }
                if gap == natural {
                    values[index] = piece
                } else if gap.isEmpty {
                    // The edit intentionally joined two Latin words. Keeping
                    // separate rendered words here would reinsert the space.
                    values[prior] += piece
                    continue
                } else if index > lastLocal && !Self.endsInNewline(values[prior])
                            && (!gap.contains("\n") || Self.endsInNewline(gap)) {
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
        if !gap.isEmpty { values[preceding ?? lastLocal] += gap }

        var emittedBreaks = Set<Int64>()
        let rows = zip(local, values).compactMap { span, value -> VoicePanelEdit? in
            let paragraph = span.entry.paragraphID
            let changedBreak = hiddenBreaks[paragraph].flatMap { hidden in
                hidden != span.entry.paragraphBreakHidden && emittedBreaks.insert(paragraph).inserted ? hidden : nil
            }
            guard !span.entry.displayText.utf16.elementsEqual(value.utf16) || changedBreak != nil else { return nil }
            return VoicePanelEdit(id: span.entry.id, before: span.entry.displayText, after: value,
                                  paragraphBreakHidden: changedBreak,
                                  previousParagraphBreakHidden: changedBreak == nil ? nil : span.entry.paragraphBreakHidden)
        }
        let reconstructed = Self.render(entries,
            replacing: Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.after) }),
            hiddenBreaks: hiddenBreaks)
        let expected = (text as NSString).replacingCharacters(in: range, with: replacement)
        guard reconstructed.text.utf16.elementsEqual(expected.utf16) else { return nil }
        let caret = range.location + replacement.utf16.count
        let affected = Set(local[firstLocal...lastLocal].map { $0.entry.id })
        if let anchor = reconstructed.spans.first(where: {
            affected.contains($0.entry.id) && ($0.range.location...NSMaxRange($0.range)).contains(caret)
        }) ?? reconstructed.spans.first(where: { ($0.range.location...NSMaxRange($0.range)).contains(caret) }) {
            return Edit(rows: rows, anchor: anchor.entry.id, offset: caret - anchor.range.location)
        }
        return Edit(rows: rows, anchor: local[firstLocal].entry.id, offset: 0)
    }
}
