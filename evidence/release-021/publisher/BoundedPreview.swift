// Research only. Neither experiment is selected for production.
// Full raw candidates only; stable UTF-16 remains zero until the original EOS.
import Foundation

struct BoundedPreview {
    let rejectReturns: Bool
    private var gate = Baseline563(model: .qwen)
    private var rawPrevious = ""
    private var retired: [Int: Set<Character>] = [:]
    private(set) var presentation = ""

    mutating func accept(_ text: String, final: Bool) -> Int? {
        if final { presentation = text; return text.utf16.count }
        defer { rawPrevious = text }
        var proposed = gate
        let accepted = proposed.accept(text, final: false)
        if accepted != nil, canPublish(text) {
            gate = proposed
            publish(text)
            return 0
        }
        gate = proposed
        // A bounded local spelling change in already visible Chinese text may
        // coexist with independently corroborated new speech. Do not assemble
        // unchanged old words with a new tail: show the complete current raw text.
        let old = units(presentation), prior = units(rawPrevious), next = units(text)
        guard old.count >= 20, prior.count > old.count, next.count >= prior.count else { return nil }
        let changed = old.indices.filter { old[$0] != next[$0] }
        guard !changed.isEmpty, changed.count <= 4,
              changed.allSatisfy({ ordinaryHan(old[$0]) && ordinaryHan(next[$0]) }),
              zip(prior.dropFirst(old.count), next.dropFirst(old.count)).prefix(while: { $0 == $1 }).count >= 2,
              next.count - old.count >= 4 else { return nil }
        // Every revised old span must have unchanged context on both sides.
        let groups = changed.reduce(into: [[Int]]()) { groups, index in
            if groups.last?.last == index - 1 { groups[groups.count - 1].append(index) }
            else { groups.append([index]) }
        }
        guard groups.count <= 2, groups.allSatisfy({ group in
            let start = group.first!, end = group.last! + 1
            return group.count <= 3 && start >= 6 && end + 6 <= old.count
                && old[(start-6)..<start].elementsEqual(next[(start-6)..<start])
                && old[end..<(end+6)].elementsEqual(next[end..<(end+6)])
        }), canPublish(text) else { return nil }
        publish(text)
        return 0
    }

    private func units(_ s: String) -> [Character] {
        // Preserve Latin, signs, decimals and digits. Only remove Chinese
        // phrase punctuation for this research alignment.
        Array(s.filter { !"。，、—".contains($0) })
    }
    private func ordinaryHan(_ c: Character) -> Bool {
        c.unicodeScalars.count == 1 && c.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) }
            && !c.isNumber && !"不没無无未非否别別勿莫甭负負".contains(c)
    }
    private func canPublish(_ text: String) -> Bool {
        guard rejectReturns else { return true }
        return !units(text).enumerated().contains { retired[$0.offset]?.contains($0.element) == true }
    }
    private mutating func publish(_ text: String) {
        let old = units(presentation), next = units(text)
        for i in 0..<min(old.count, next.count) where old[i] != next[i] {
            retired[i, default: []].insert(old[i])
        }
        presentation = text
    }
}
