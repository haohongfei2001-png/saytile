import Foundation

/// Evidence for an early, complete acoustic phrase. The panel continues to show
/// the whole current hypothesis; this boundary alone may enter owned direct input.
/// Confirmation is not immutable model finality. A changed head stops appends;
/// only the exact EOS can later request the existing owned-range correction.
struct QwenPrefixConfirmation {
    private struct Observation { let text: String; let frames: Int }
    private var history: [Observation] = []
    private(set) var confirmed = ""

    mutating func accept(_ text: String, frames: Int) -> Int {
        guard frames > (history.last?.frames ?? -1) else { return 0 }
        history.append(.init(text: text, frames: frames))
        if history.count > 6 { history.removeFirst(history.count - 6) }
        guard history.count >= 4,
              RecognitionUTF16.hasExactPrefix(text, prefix: confirmed) else { return 0 }
        let recent = Array(history.suffix(4))
        guard frames - recent[0].frames >= 16_000 else { return 0 }
        let agreement = RecognitionUTF16.commonPrefix(recent.map(\.text))
        // Following speech distinguishes an internal phrase boundary from
        // Qwen's temporary trailing full stop; it does not prove final accuracy.
        let supported = agreement.dropLast(8)
        guard let boundary = supported.lastIndex(where: { "，。；！？,;!?".contains($0) }) else { return 0 }
        let phrase = String(supported[...boundary])
        guard phrase.utf16.count > confirmed.utf16.count,
              RecognitionUTF16.hasExactPrefix(phrase, prefix: confirmed) else {
            return confirmed.utf16.count
        }
        if phrase.contains(where: { $0.isNumber || "一二三四五六七八九十百千万萬亿億零〇两兩壹贰叁肆伍陆柒捌玖拾佰仟不没無无未非否别別勿莫甭负負+-−¥￥$€%％".contains($0) }) {
            guard history.count == 6, frames - history[0].frames >= 32_000,
                  history.allSatisfy({ RecognitionUTF16.hasExactPrefix($0.text, prefix: phrase) }) else {
                return confirmed.utf16.count
            }
        }
        confirmed = phrase
        return phrase.utf16.count
    }
}
