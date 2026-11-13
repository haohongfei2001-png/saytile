import Foundation

/// Aggregates replaceable audio ranges. Only the leading sequence of finalized
/// ranges is eligible for direct insertion; a volatile tail is always kept apart.
struct SpeechResultAccumulator {
    struct Snapshot: Equatable {
        let fullText: String
        let stableText: String
        let isCompletelyFinal: Bool
    }
    private struct Piece {
        let start: Double
        let end: Double
        let text: String
        var isFinal: Bool
        var finalPunctuation = ""
        var displayedText: String { text + finalPunctuation }
    }
    private var pieces: [Piece] = []
    private var finalizedThrough: Double = 0
    private(set) var snapshot = Snapshot(fullText:"",stableText:"",isCompletelyFinal:false)
    @discardableResult mutating func apply(start: Double, end: Double, text: String, isFinal: Bool, finalizedThrough: Double? = nil) -> Snapshot {
        guard start.isFinite, end.isFinite, end >= start else { return snapshot }
        if start == end {
            // Speech can emit final punctuation twice at the exact end of a finalized range.
            guard isFinal, !text.isEmpty, text.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains),
                  let index = pieces.lastIndex(where: { $0.end == end && $0.isFinal && !$0.text.isEmpty }) else { return snapshot }
            pieces[index].finalPunctuation = pieces[index].text.hasSuffix(text) ? "" : text
            return rebuildSnapshot()
        }
        pieces.removeAll { $0.start < end && $0.end > start }
        pieces.append(Piece(start: start, end: end, text: Self.typeset(text),
                            isFinal: isFinal || end <= self.finalizedThrough))
        pieces.sort { $0.start < $1.start }
        if let finalizedThrough { markFinalized(through: finalizedThrough) }
        return rebuildSnapshot()
    }
    @discardableResult mutating func advanceFinalization(through: Double) -> Snapshot {
        markFinalized(through: through)
        return rebuildSnapshot()
    }
    private mutating func markFinalized(through: Double) {
        guard !through.isNaN, through > finalizedThrough else { return }
        finalizedThrough = through
        for index in pieces.indices where pieces[index].end <= through { pieces[index].isFinal = true }
    }
    // Apple inserts an ASCII space before some Chinese punctuation within a result.
    // Keep all word boundaries, newlines, and other characters in the recognizer's text.
    private static func typeset(_ text: String) -> String {
        guard text.utf8.contains(0x20) else { return text }
        var output = ""
        output.reserveCapacity(text.utf8.count)
        for character in text {
            if "，。！？；：、".contains(character) {
                while output.last == " " { output.removeLast() }
            }
            output.append(character)
        }
        return output
    }
    private mutating func rebuildSnapshot() -> Snapshot {
        let stable = pieces.prefix { $0.isFinal }.map(\.displayedText).joined()
        snapshot = Snapshot(fullText:pieces.map(\.displayedText).joined(),stableText:stable,isCompletelyFinal:!pieces.isEmpty && pieces.allSatisfy(\.isFinal))
        return snapshot
    }
}
