/// Rolling Qwen may revise an established word after prolonged unchanged
/// previews. Ask for one more observation sooner, with new audio. This is
/// scheduling only. It neither confirms text nor bypasses preview ownership.
enum QwenConfirmationCadence {
    static func shouldConfirm(previous: String, candidate: String, changedAfterFrames: Int) -> Bool {
        guard changedAfterFrames >= 16_000 else { return false }
        // Only the scheduler reads this alignment. The gate still receives
        // each complete, verbatim worker hypothesis and independently owns text.
        func words(_ text: String) -> [Character] {
            text.filter { !"。，、".contains($0) }
        }
        let old = words(previous), new = words(candidate)
        guard old.count >= 16, new.count >= old.count + 2 else { return false }
        var first: Int?, last = 0
        for i in old.indices where old[i] != new[i] {
            first = first ?? i
            last = i
            if let first, last - first >= 4 { return false }
        }
        guard first != nil, old.count - last > 8 else { return false }
        // Ignore a full stop, ellipsis or whitespace masquerading as growth.
        return new[old.count...].contains { $0.isLetter || $0.isNumber }
    }
}
