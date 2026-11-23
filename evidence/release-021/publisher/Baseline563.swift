import Foundation
enum LocalASRID { case qwen, qwenLarge, nemotron, apple }
public enum RecognitionUTF16 {
    /// Both ends must be complete extended grapheme boundaries, including emoji/combining marks.
    public static func slice(_ text: String, start: Int, end: Int) -> String? {
        guard start >= 0, end >= start, end <= text.utf16.count else { return nil }
        let units = text.utf16
        let lower = units.index(units.startIndex, offsetBy: start)
        let upper = units.index(units.startIndex, offsetBy: end)
        guard let lo = String.Index(lower, within: text), let hi = String.Index(upper, within: text),
              (lo == text.endIndex || text.indices.contains(lo)),
              (hi == text.endIndex || text.indices.contains(hi)) else { return nil }
        return String(text[lo..<hi])
    }
    public static func hasExactPrefix(_ text: String, prefix: String) -> Bool {
        text.utf16.starts(with: prefix.utf16) && slice(text, start: 0, end: prefix.utf16.count) != nil
    }
    public static func commonPrefix(_ texts: [String]) -> String {
        guard var prefix = texts.first else { return "" }
        for text in texts.dropFirst() {
            var match = ""
            for (a, b) in zip(prefix, text) { guard String(a).utf16.elementsEqual(String(b).utf16) else { break }; match.append(a) }
            prefix = match
        }
        return prefix
    }
}

struct Baseline563 {
    let model: LocalASRID
    private(set) var previous = ""
    private(set) var presentation = ""
    private var readingPrefix = ""
    private var withheld: String?
    private var unconfirmedTail: String?
    init(model: LocalASRID) { self.model = model }
    mutating func accept(_ text: String, final: Bool) -> Int? {
        if final {
            presentation = text
            return text.utf16.count
        }
        let common = RecognitionUTF16.commonPrefix([previous, text])
        if model == .qwen || model == .qwenLarge {
            if let correction = Self.tailOnlyCorrection(previous: previous, text: text),
               unconfirmedTail != correction {
                // A single unchanged-length tail spelling is not new speech.
                // Keep the last observed words until this correction is repeated
                // or fresh speech arrives. EOS always bypasses this preview gate.
                unconfirmedTail = correction
                return nil
            }
            unconfirmedTail = nil
            // The zh decoder can change the script of the whole hypothesis mid-utterance.
            // Compare scripts only for preview ownership. Publish the original model string.
            let matches = RecognitionUTF16.hasExactPrefix(text, prefix: readingPrefix)
            if !matches, let reference = readingPrefix.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false),
               let candidate = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false),
               candidate.hasPrefix(reference), !reference.isEmpty {
                readingPrefix = String(text.prefix(readingPrefix.count))
            } else if !matches, let mapped = Self.formattedPrefix(readingPrefix, in: text) {
                // The decoder can restyle an earlier English phrase on every pass
                // while correctly extending the tail. Compare only the protected
                // preview prefix. Never synthesize display text or grant dispatch.
                readingPrefix = mapped
            } else if !matches {
                // A decoder may permanently change “二十九岁” to “29岁”. Suppressing
                // every later hypothesis would freeze the preview until end of speech.
                // Require two concordant passes. For a change deep in a long
                // preview, the rest of the already visible words must still align.
                let prior = withheld
                withheld = text
                guard let prior else { return nil }
                if let prefix = Self.confirmedReadingPrefix(previous: previous, prior: prior, text: text, unchanged: common.count)
                    ?? Self.locallyConfirmedPrefix(previous: previous, prior: prior, text: text)
                    ?? Self.confirmedLatinSpacing(previous: previous, prior: prior, text: text) {
                    readingPrefix = prefix
                } else { return nil }
            } else if common.count > 8 {
                let supported = String(common.dropLast(8))
                if supported.utf16.count > readingPrefix.utf16.count { readingPrefix = supported }
            }
            withheld = nil
        }
        // The rolling decoder ends almost every intermediate hypothesis with a
        // full stop, including on the first word. Reveal the words immediately.
        // Internal punctuation and the eventual verbatim final are preserved.
        if (model == .qwen || model == .qwenLarge),
           text.last == "。", text.count > 1, !previous.hasPrefix(text) {
            presentation = String(text.dropLast())
        } else {
            presentation = text
        }
        previous = text
        return model == .nemotron ? String(common.dropLast()).utf16.count : 0
    }

    private static func tailOnlyCorrection(previous: String, text: String) -> String? {
        let old = Array(previous.filter { $0.isLetter || $0.isNumber })
        let current = Array(text.filter { $0.isLetter || $0.isNumber })
        guard old.count >= 12, old.count == current.count else { return nil }
        let changed = old.indices.filter { old[$0] != current[$0] }
        guard let first = changed.first, let last = changed.last,
              first >= max(8, old.count - 8), last - first < 3 else { return nil }
        func ordinaryHan(_ c: Character) -> Bool {
            c.unicodeScalars.count == 1 && c.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) }
                && !protectsBoundary(c)
        }
        guard changed.allSatisfy({ ordinaryHan(old[$0]) && ordinaryHan(current[$0]) }) else { return nil }
        // Comparison only: the actual displayed string still comes from the
        // current raw hypothesis, after all existing ownership checks below.
        return String(current)
    }

    private static func confirmedReadingPrefix(previous: String, prior: String, text: String, unchanged: Int) -> String? {
        let supported = RecognitionUTF16.commonPrefix([prior, text])
        guard text.count >= previous.count,
              supported.count >= max(unchanged + 4, min(previous.count, 12)) else { return nil }
        if previous.count - unchanged <= 24 {
            let oldTail = Array(previous.dropFirst(unchanged))
            let newTail = String(supported.dropFirst(unchanged).prefix(48))
            guard oldTail.count >= 4, (0...(oldTail.count - 4)).contains(where: { i in
                let anchor = oldTail[i..<(i + 4)]
                return anchor.allSatisfy { $0.isLetter || $0.isNumber } && newTail.contains(String(anchor))
            }) else { return nil }
        } else if !Self.hasLocalizedCorrection(from: previous, to: supported) { return nil }
        return String(supported.dropLast(8))
    }

    // In mixed speech Qwen may split an earlier compound ("smartphone" to
    // "smart phone") while appending Chinese words. Spaces can change meaning.
    // Accept the complete current hypothesis only after a second observation
    // confirms the changed boundary, the entire old text, and fresh speech.
    private static func confirmedLatinSpacing(previous: String, prior: String, text: String) -> String? {
        func latin(_ c: Character) -> Bool {
            guard let n = c.asciiValue else { return false }
            return (65...90).contains(n) || (97...122).contains(n)
        }
        func units(_ value: String) -> [(Character, String.Index)] {
            var result: [(Character, String.Index)] = []
            for i in value.indices {
                let c = value[i], next = value.index(after: i)
                if c == "。", next == value.endIndex { continue }
                if c == "，", i > value.startIndex, next < value.endIndex {
                    let before = value[value.index(before: i)], after = value[next]
                    if before.isLetter, after.isLetter, !protectsBoundary(before), !protectsBoundary(after) { continue }
                }
                result.append((latin(c) ? Character(c.lowercased()) : c, next))
            }
            return result
        }
        let original = units(previous).map(\.0), proposal = units(text)
        let current = proposal.map(\.0)
        let i = zip(original, current).prefix(while: { $0 == $1 }).count
        guard i >= 2, i < min(original.count, current.count), original[..<i].suffix(2).allSatisfy(latin) else { return nil }
        let inserting = current[i] == " "
        guard inserting != (original[i] == " ") else { return nil }
        var corrected = original
        if inserting { corrected.insert(" ", at: i) } else { corrected.remove(at: i) }
        let after = i + (inserting ? 1 : 0)
        let right = corrected[after...].prefix(while: latin)
        let following = corrected.dropFirst(after + right.count)
        guard right.count >= 2, following.count >= 6, following.prefix(6).allSatisfy({ $0.isLetter }),
              current.starts(with: corrected) else { return nil }
        let observed = units(prior).map(\.0)
        guard observed.starts(with: corrected),
              observed.dropFirst(corrected.count).contains(where: { $0.isLetter || $0.isNumber }),
              current.dropFirst(corrected.count).contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return String(text[..<proposal[corrected.count - 9].1])
    }

    // Changing a boundary next to a number or negative can change the meaning
    // even when the surrounding spoken words are unchanged.
    private static func protectsBoundary(_ c: Character?) -> Bool {
        guard let c else { return false }
        return c.isNumber || "不没無无未非否别別勿莫甭负負".contains(c)
    }

    /// Two growing passes can agree about a local correction while disagreeing
    /// at an earlier word that the current pass leaves exactly as last displayed.
    /// Only accept a whole current hypothesis, never splice corrected words.
    private static func locallyConfirmedPrefix(previous: String, prior: String, text: String) -> String? {
        // Ignore Chinese phrase punctuation for alignment only. Preserve number
        // punctuation, word boundaries, signs and all non-Han lexical units.
        func units(_ raw: String) -> [(Character, String.Index)] {
            var result: [(Character, String.Index)] = []
            var i = raw.startIndex
            while i < raw.endIndex {
                let c = raw[i], next = raw.index(after: i)
                let before = i == raw.startIndex ? nil : raw[raw.index(before: i)]
                let after = next == raw.endIndex ? nil : raw[next]
                if c == "—", after == "—", let before, before.isLetter, !protectsBoundary(before) {
                    let end = raw.index(after: next)
                    if end < raw.endIndex, raw[end].isLetter, !protectsBoundary(raw[end]) { i = end; continue }
                }
                if !("。，、".contains(c) && !protectsBoundary(before) && !protectsBoundary(after)) {
                    result.append((c, next))
                }
                i = next
            }
            return result
        }
        let old = units(previous).map(\.0), observed = units(prior).map(\.0), mapped = units(text)
        let current = mapped.map(\.0)
        guard old.count >= 20, current.count >= old.count + 2,
              observed.count > old.count, current.count >= observed.count else { return nil }
        let changes = old.indices.filter { old[$0] != current[$0] }
        guard let first = changes.first, let last = changes.last else { return nil }
        func ordinaryHan(_ c: Character) -> Bool {
            c.unicodeScalars.count == 1 && c.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) }
                && !protectsBoundary(c)
        }
        guard changes.allSatisfy({ ordinaryHan(old[$0]) && ordinaryHan(current[$0]) }) else { return nil }
        // A shared space or an ellipsis does not substantiate a new word.
        let extensionAgreement = zip(current[old.count...], observed[old.count...]).prefix { $0 == $1 }
        guard extensionAgreement.contains(where: { $0.0.isLetter || $0.0.isNumber }) else { return nil }

        let anchorEnd: Int
        let clusters = changes.reduce(into: [[Int]]()) { groups, index in
            if let end = groups.last?.last, index == end + 1 { groups[groups.count - 1].append(index) }
            else { groups.append([index]) }
        }
        if clusters.count == 2, clusters.allSatisfy({ $0.count <= 3 }), first >= 12,
           clusters[1][0] - clusters[0].last! >= 4, old.count - last > 12 {
            // Two independent earlier Chinese words can settle on the same pass.
            // Both raw observations must corroborate the ENTIRE visible lexical
            // span, not just a shared phrase. Reject numbers, negatives, changed
            // word lengths and broad rewrites above; publish only the raw model
            // hypothesis. Final text and external dispatch remain independent.
            guard observed.prefix(old.count).elementsEqual(current.prefix(old.count)) else { return nil }
            anchorEnd = old.count
        } else if last - first < 4, first >= 3, old.count - last > 12 {
            // A different, earlier spelling on the prior pass must not invalidate
            // the local evidence when the current pass restores the displayed words.
            guard current[(first - 3)..<old.count].elementsEqual(observed[(first - 3)..<old.count]) else { return nil }
            let earlier = (0..<(first - 3)).filter { observed[$0] != current[$0] }
            if let a = earlier.first, let b = earlier.last {
                guard b - a < 4, earlier.allSatisfy({ ordinaryHan(observed[$0]) && ordinaryHan(current[$0]) }) else { return nil }
            } else if !current.starts(with: observed) {
                // Without an independent earlier change, this fallback admits
                // only a whole corroborated lexical hypothesis and its exact
                // extension. New speech must not invalidate already matching
                // words, but a changed word in the observed tail still does.
                return nil
            }
            anchorEnd = old.count
        } else {
            // A short unfinished word at the old right edge can be corrected at
            // the same time as one older word. Both passes must corroborate the
            // *whole* corrected old span, then grow beyond it with real words.
            let tail = changes.drop { $0 - first < 4 }
            guard let tailStart = tail.first, tailStart >= old.count - 3,
                  let earlyEnd = changes.last(where: { $0 < tailStart }), tailStart - earlyEnd > 12,
                  observed.prefix(old.count).elementsEqual(current.prefix(old.count)),
                  current[observed.count...].contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            anchorEnd = tailStart
        }
        let offset = anchorEnd - 12, anchor = old[offset..<anchorEnd]
        func unique(_ words: [Character]) -> Bool {
            !(0...(words.count - anchor.count)).contains { i in
                i != offset && words[i...].starts(with: anchor)
            }
        }
        guard unique(old), unique(observed), unique(current) else { return nil }
        // Protect only material already visible and corroborated on both passes.
        return String(text[..<mapped[old.count - 9].1])
    }

    /// Map common ASR typography to the exact raw end index in the new pass.
    /// Keep word boundaries, signs, numbers, and lexical changes distinct.
    private static func formattedPrefix(_ raw: String, in candidate: String) -> String? {
        guard !raw.isEmpty else { return nil }
        func latin(_ c: Character?) -> Bool {
            guard let n = c?.asciiValue else { return false }
            return (65...90).contains(n) || (97...122).contains(n)
        }
        enum Unit: Equatable { case literal(Character), pause }
        func units(_ text: String, alignPauses: Bool) -> [(Unit, String.Index)] {
            var out: [(Unit, String.Index)] = []
            var i = text.startIndex
            while i < text.endIndex {
                let c = text[i], next = text.index(after: i)
                var end = next
                defer { i = end }
                let before = i == text.startIndex ? nil : text[text.index(before: i)]
                let after = next == text.endIndex ? nil : text[next]
                let protected = protectsBoundary(before) || protectsBoundary(after)
                if !alignPauses, c == "，", !protected { continue }
                let mapped: Unit
                if alignPauses, !protected, c == "。" || c == "，" || c == "、" {
                    mapped = .pause
                } else if alignPauses, c == "—", after == "—", before?.isLetter == true,
                          !protected, text.index(after: next) < text.endIndex,
                          text[text.index(after: next)].isLetter, !protectsBoundary(text[text.index(after: next)]) {
                    // A Chinese double dash can mark an apposition. A minus,
                    // single dash, numeric range or moved boundary stays distinct.
                    end = text.index(after: next)
                    mapped = .pause
                } else if c == "-", latin(before), latin(after) { mapped = .literal(" ") }
                else if latin(c) { mapped = .literal(Character(c.lowercased())) }
                else { mapped = .literal(c) }
                out.append((mapped, end))
            }
            return out
        }
        // First preserve the existing optional-comma comparison. If that fails,
        // require an actual phrase boundary on both sides at the same position.
        for alignPauses in [false, true] {
            let prefix = units(raw, alignPauses: alignPauses), update = units(candidate, alignPauses: alignPauses)
            if !prefix.isEmpty, update.count >= prefix.count,
               zip(prefix, update).allSatisfy({ $0.0.0 == $0.1.0 }) {
                return String(candidate[..<update[prefix.count - 1].1])
            }
        }
        return nil
    }

    private static func hasLocalizedCorrection(from visible: String, to confirmed: String) -> Bool {
        // Ignore sentence punctuation for alignment only. Preserve digits, signs
        // and the raw model string used for display. No partial becomes stable.
        let punctuation = CharacterSet(charactersIn: "，。！？、；：,—!?;:“”「」").union(.whitespacesAndNewlines)
        func words(_ text: String) -> [Character] {
            text.filter { !$0.unicodeScalars.allSatisfy(punctuation.contains) }
        }
        let old = words(visible), new = words(confirmed)
        let common = zip(old, new).prefix(while: { $0 == $1 }).count
        let oldTail = old.dropFirst(common), newTail = new.dropFirst(common)
        if oldTail.isEmpty { return old.count >= 12 }
        for removed in 0...min(4, oldTail.count) {
            let suffix = oldTail.dropFirst(removed)
            guard suffix.count >= 12 else { break }
            for inserted in 0...min(4, newTail.count) where newTail.dropFirst(inserted).starts(with: suffix) {
                return true
            }
        }
        return false
    }
}
