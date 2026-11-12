import Foundation

/// Aggregates replaceable audio ranges. Only the leading sequence of finalized
/// ranges is eligible for direct insertion; a volatile tail is always kept apart.
struct SpeechResultAccumulator {
    struct Snapshot: Equatable {
        let fullText: String
        let stableText: String
        let isCompletelyFinal: Bool
    }
    private struct Piece { let start: Double; let end: Double; let text: String; var isFinal: Bool }
    private var pieces: [Piece] = []
    private var finalizedThrough: Double = 0
    private(set) var snapshot = Snapshot(fullText:"",stableText:"",isCompletelyFinal:false)
    @discardableResult mutating func apply(start: Double, end: Double, text: String, isFinal: Bool, finalizedThrough: Double? = nil) -> Snapshot {
        guard start.isFinite,end.isFinite,end > start else { return snapshot }
        pieces.removeAll { $0.start < end && $0.end > start }
        pieces.append(Piece(start:start,end:end,text:text,isFinal:isFinal || end <= self.finalizedThrough))
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
    private mutating func rebuildSnapshot() -> Snapshot {
        let stable = pieces.prefix { $0.isFinal }.map(\.text).joined()
        snapshot = Snapshot(fullText:pieces.map(\.text).joined(),stableText:stable,isCompletelyFinal:!pieces.isEmpty && pieces.allSatisfy(\.isFinal))
        return snapshot
    }
}
