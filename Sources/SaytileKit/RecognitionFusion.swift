import Foundation

public struct CandidateSpan: Codable, Sendable, Equatable {
    public let candidateID: UUID
    public let utf16Start: Int
    public let utf16End: Int
    public init(candidateID: UUID, utf16Start: Int, utf16End: Int) {
        self.candidateID = candidateID; self.utf16Start = utf16Start; self.utf16End = utf16End
    }
}

/// A proposal is evidence selection, never unconstrained rewritten prose.
public struct FusionProposal: Codable, Sendable, Equatable {
    public let previewText: String
    public let stableText: String
    public let sourceCandidateIDs: [UUID]
    public let unresolved: Bool
    public let needsAudioReview: Bool
    public let reasonCode: String
    public let selections: [CandidateSpan]
    public let selectionRequestedUnresolved: Bool?
    public let reviewedCandidateIDs: [UUID]?
    // Only the deterministic engine constructs publishable proposals. Store revalidates sources.
    init(previewText: String, stableText: String, sourceCandidateIDs: [UUID], unresolved: Bool,
         needsAudioReview: Bool, reasonCode: String, selections: [CandidateSpan] = [], selectionRequestedUnresolved: Bool? = nil, reviewedCandidateIDs: [UUID]? = nil) {
        self.previewText = previewText; self.stableText = stableText; self.sourceCandidateIDs = sourceCandidateIDs
        self.unresolved = unresolved; self.needsAudioReview = needsAudioReview; self.reasonCode = reasonCode
        self.selections = selections; self.selectionRequestedUnresolved = selectionRequestedUnresolved; self.reviewedCandidateIDs = reviewedCandidateIDs
    }
}

public struct FusionPublication: Sendable, Equatable {
    public let revision: TranscriptRevision?
    public let published: Bool
    public let deferred: Bool
}
public struct FusionDecisionRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let recognitionID: UUID
    public let proposal: FusionProposal
    public let revisionID: UUID?
    public let outcome: String
    public let createdAt: Date
}

/// Deliberately conservative baseline. Exact agreement is usable evidence, not a guarantee of truth.
/// Utterance-only timestamps cannot justify word-level cross-model splicing.
public enum PrecisionFusion {
    public static func evaluate(candidates: [RecognitionCandidate], mode: InputQualityMode,
                                committedPrefix: String = "",
                                requiredPurposes: Set<RecognitionPurpose> = [.chineseASR, .englishASR]) -> FusionProposal {
        let valid = candidates.filter { (try? validateCandidate($0)) != nil }
        let live = latestPerRun(valid).filter { $0.run.purpose != .textFusion }
        guard let preview = live.sorted(by: previewOrder).first else {
            return FusionProposal(previewText: committedPrefix, stableText: committedPrefix,
                                  sourceCandidateIDs: [], unresolved: true, needsAudioReview: false, reasonCode: "waiting-candidates")
        }
        // The same audio origin is required for exact-prefix comparison. Do not align by text length.
        let sameOrigin = live.filter { $0.run.recordingID == preview.run.recordingID && $0.run.recognitionID == preview.run.recognitionID && $0.run.audioEpoch == preview.run.audioEpoch && abs($0.audioStartSeconds - preview.audioStartSeconds) < 0.001 }
        let compared: [RecognitionCandidate]
        if mode == .highestQuality {
            guard Set(sameOrigin.map { $0.run.purpose }).isSuperset(of: requiredPurposes) else {
                return FusionProposal(previewText: preview.text, stableText: committedPrefix,
                    sourceCandidateIDs: sameOrigin.map(\.id), unresolved: true, needsAudioReview: false, reasonCode: "waiting-language-experts")
            }
            // Include actual acoustic review evidence when present; do not outvote it.
            compared = sameOrigin
        } else {
            compared = sameOrigin.filter { roleSupports(text: $0.stableText, run: $0.run) }
            guard !compared.isEmpty else {
                return FusionProposal(previewText: preview.text, stableText: committedPrefix,
                    sourceCandidateIDs: sameOrigin.map(\.id), unresolved: true, needsAudioReview: true, reasonCode: "language-support-uncertain")
            }
        }
        let rawCommon = RecognitionUTF16.commonPrefix(compared.map(\.stableText))
        let common = Set(compared.map(\.stableText)).count > 1 ? completeLexicalPrefix(rawCommon) : rawCommon
        let stable = RecognitionUTF16.hasExactPrefix(common, prefix: committedPrefix) ? common : committedPrefix
        let texts = compared.map(\.text)
        let disagreement = Set(texts).count > 1
        let critical = Set(compared.map { protectedSignature($0.text) }).count > 1
        // Even when a provider labels its entire text final, disagreement remains unresolved.
        return FusionProposal(previewText: preview.text, stableText: stable,
            sourceCandidateIDs: compared.map(\.id), unresolved: disagreement || stable != preview.text,
            needsAudioReview: disagreement && critical, reasonCode: disagreement ? "acoustic-disagreement" : "exact-stable-agreement")
    }

    /// Validate an LLM's exact source spans. No generated characters, confidence comparisons or
    /// inferred timing are accepted. Unknown alignment leaves the original alternatives intact.
    public static func validateSelection(spans: [CandidateSpan], candidates: [RecognitionCandidate],
                                         committedPrefix: String = "", unresolved: Bool = false,
                                         needsAudioReview: Bool = false,
                                         reasonCode: String = "evidence-selection") throws -> FusionProposal {
        guard spans.count <= 4096, reasonCode.count <= 400 else { throw FusionError.invalidSelection }
        if let origin = candidates.first?.run {
            guard candidates.allSatisfy({ $0.run.recordingID == origin.recordingID && $0.run.recognitionID == origin.recognitionID && $0.run.audioEpoch == origin.audioEpoch }) else { throw FusionError.invalidSelection }
        }
        let index = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var text = "", previousEnd: Double?, selected: [RecognitionCandidate] = []
        var allStable = true
        var previousSpan: CandidateSpan?
        for span in spans {
            guard let candidate = index[span.candidateID], span.utf16End > span.utf16Start,
                  let value = RecognitionUTF16.slice(candidate.text, start: span.utf16Start, end: span.utf16End) else { throw FusionError.invalidSelection }
            try validateCandidate(candidate)
            guard candidate.run.purpose != .textFusion else { throw FusionError.invalidSelection }
            let interval = try audioInterval(span: span, candidate: candidate)
            if let previousEnd {
                // Shared token boundaries may differ slightly across providers; larger overlap or
                // a gap is not evidence that omitted/duplicated speech is safe.
                guard interval.start >= previousEnd - 0.08, interval.start <= previousEnd + 0.08 else { throw FusionError.insufficientAlignment }
            }
            if let previousSpan, previousSpan.candidateID == span.candidateID {
                guard previousSpan.utf16End == span.utf16Start else { throw FusionError.invalidSelection }
            }
            guard roleSupports(text: value, run: candidate.run) ||
                    corroborated(value: value, candidate: candidate, interval: interval, candidates: candidates) else { throw FusionError.insufficientAlignment }
            previousEnd = interval.end; previousSpan = span
            text += value; selected.append(candidate)
            allStable = allStable && span.utf16End <= candidate.stableUTF16Length
        }
        // A whole-utterance selection must preserve the utterance's beginning. Prefix omission is
        // permitted only when it is already confirmed verbatim; callers cannot remove a negation.
        if let first = spans.first, let candidate = index[first.candidateID] {
            guard candidate.audioStartSeconds < 0.001 else { throw FusionError.insufficientAlignment }
            guard first.utf16Start == 0 || !committedPrefix.isEmpty &&
                  RecognitionUTF16.slice(candidate.text, start: 0, end: first.utf16Start) == committedPrefix else { throw FusionError.invalidSelection }
            if first.utf16Start > 0 { text = committedPrefix + text }
        }
        var protectedConflict = false
        if let first = selected.first {
            let relevant = candidates.filter {
                abs($0.audioStartSeconds - first.audioStartSeconds) < 0.5 &&
                $0.audioEndSeconds >= first.audioStartSeconds && $0.run.purpose != .textFusion
            }
            let signature = protectedSignature(text)
            let horizon = previousEnd ?? first.audioEndSeconds
            func criticalEvidence(_ candidate: RecognitionCandidate) -> String {
                // Only actual timed boundaries can exclude later critical words. A plain string
                // prefix is insufficient: "100" is also a prefix of the conflicting "1000".
                return protectedSignature(evidencePrefix(candidate, through: horizon) ?? candidate.text)
            }
            let differs = relevant.contains { criticalEvidence($0) != signature }
            // Only an additional direct-audio source that corroborates the selected critical
            // content can resolve this guard; a text LLM's self-reported confidence cannot.
            let matching = relevant.filter { criticalEvidence($0) == signature }
            let independent = Set(matching.map { $0.run.provider + ":" + $0.run.model }).count >= 2
            let hasRecheck = matching.contains { [.audioReview, .finalASR].contains($0.run.purpose) && $0.isComplete && $0.stableUTF16Length == $0.text.utf16.count }
            protectedConflict = differs && !(independent && hasRecheck)
        }
        let uncertain = unresolved || needsAudioReview || protectedConflict || !allStable
        let changesCommitted = !RecognitionUTF16.hasExactPrefix(text, prefix: committedPrefix)
        let truncatedSource: Bool
        if let last = spans.last, let source = index[last.candidateID] { truncatedSource = last.utf16End < source.text.utf16.count }
        else { truncatedSource = true }
        return FusionProposal(previewText: text, stableText: uncertain || changesCommitted ? committedPrefix : text,
            sourceCandidateIDs: Array(Set(selected.map(\.id))).sorted { $0.uuidString < $1.uuidString },
            unresolved: uncertain || changesCommitted || truncatedSource, needsAudioReview: needsAudioReview || protectedConflict,
            reasonCode: protectedConflict ? "protected-content-needs-audio" : changesCommitted ? "late-correction-preserved" : reasonCode,
            selections: spans, selectionRequestedUnresolved: unresolved, reviewedCandidateIDs: candidates.map(\.id))
    }

    /// An in-flight LLM may finish after providers append more speech. Reuse its decision only
    /// when all evidence inside the selected audio window still matches the same runs exactly.
    /// A restarted run, changed prior word, missing source or newly arrived source requires review.
    public static func rebaseSelection(spans: [CandidateSpan], previousCandidates: [RecognitionCandidate],
                                       currentCandidates: [RecognitionCandidate], committedPrefix: String = "",
                                       unresolved: Bool = false, needsAudioReview: Bool = false,
                                       reasonCode: String = "evidence-selection") throws -> FusionProposal {
        guard !spans.isEmpty else { throw FusionError.invalidSelection }
        let previous = Dictionary(previousCandidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let current = Dictionary(latestPerRun(currentCandidates).map { ($0.run.id, $0) }, uniquingKeysWith: { a, _ in a })
        let previousRuns = Set(previousCandidates.filter { $0.run.purpose != .textFusion }.map { $0.run.id })
        guard Set(currentCandidates.filter { $0.run.purpose != .textFusion }.map { $0.run.id }).isSubset(of: previousRuns) else { throw FusionError.staleGeneration }
        var rebased: [CandidateSpan] = [], horizon = 0.0
        for span in spans {
            guard let old = previous[span.candidateID], let now = current[old.run.id], old.run == now.run,
                  now.sequence >= old.sequence, now.sequence > old.sequence || now.id == old.id,
                  abs(now.audioStartSeconds - old.audioStartSeconds) < 0.001,
                  let oldPrefix = RecognitionUTF16.slice(old.text, start: 0, end: span.utf16End),
                  RecognitionUTF16.hasExactPrefix(now.text, prefix: oldPrefix) else { throw FusionError.staleGeneration }
            horizon = max(horizon, try audioInterval(span: span, candidate: old).end)
            rebased.append(CandidateSpan(candidateID: now.id, utf16Start: span.utf16Start, utf16End: span.utf16End))
        }
        for old in previousCandidates where old.run.purpose != .textFusion {
            guard let now = current[old.run.id], now.run == old.run, now.sequence >= old.sequence,
                  now.sequence > old.sequence || now.id == old.id,
                  abs(now.audioStartSeconds - old.audioStartSeconds) < 0.001 else { throw FusionError.staleGeneration }
            if let priorWindow = evidencePrefix(old, through: horizon),
               let currentWindow = evidencePrefix(now, through: horizon) {
                guard priorWindow.utf16.elementsEqual(currentWindow.utf16) else { throw FusionError.staleGeneration }
            } else {
                // With only an utterance interval, appended text is safe only when every old
                // character remains an exact prefix. No character-to-time interpolation.
                guard RecognitionUTF16.hasExactPrefix(now.text, prefix: old.text) else { throw FusionError.staleGeneration }
            }
        }
        let checked = try validateSelection(spans: rebased, candidates: currentCandidates,
            committedPrefix: committedPrefix, unresolved: unresolved, needsAudioReview: needsAudioReview, reasonCode: reasonCode)
        return FusionProposal(previewText: checked.previewText, stableText: checked.stableText,
            sourceCandidateIDs: checked.sourceCandidateIDs, unresolved: checked.unresolved,
            needsAudioReview: checked.needsAudioReview, reasonCode: checked.reasonCode, selections: checked.selections,
            selectionRequestedUnresolved: checked.selectionRequestedUnresolved, reviewedCandidateIDs: previousCandidates.map(\.id))
    }

    /// Returns a complete textual prefix backed by actual token/segment boundaries. Nil means
    /// the requested time falls inside an indivisible segment or has no usable alignment.
    static func evidencePrefix(_ candidate: RecognitionCandidate, through horizon: Double) -> String? {
        if candidate.audioEndSeconds <= horizon + 0.001 { return candidate.text }
        guard let mapped = try? mappedTokens(candidate) else { return nil }
        var end = 0
        for item in mapped {
            if item.token.startSeconds >= horizon - 0.001 { break }
            guard item.token.endSeconds <= horizon + 0.08 else { return nil }
            end = item.end
        }
        return RecognitionUTF16.slice(candidate.text, start: 0, end: end)
    }

    public static func validateCandidate(_ candidate: RecognitionCandidate) throws {
        guard candidate.sequence >= 0, candidate.audioStartSeconds.isFinite,
              candidate.audioEndSeconds.isFinite, candidate.audioStartSeconds >= 0,
              candidate.audioEndSeconds >= candidate.audioStartSeconds,
              candidate.createdAt.timeIntervalSince1970.isFinite,
              RecognitionUTF16.slice(candidate.text, start: 0, end: candidate.stableUTF16Length) != nil,
              !candidate.run.provider.isEmpty, !candidate.run.model.isEmpty else { throw FusionError.invalidCandidate }
        var previousStart = candidate.audioStartSeconds
        for token in candidate.tokens {
            guard token.startSeconds.isFinite, token.endSeconds.isFinite,
                  token.startSeconds >= candidate.audioStartSeconds - 0.08,
                  token.endSeconds <= candidate.audioEndSeconds + 0.08,
                  token.endSeconds >= token.startSeconds, token.startSeconds >= previousStart,
                  token.rawConfidence?.isFinite != false else { throw FusionError.invalidCandidate }
            previousStart = token.startSeconds
        }
    }

    public static func stableAudioEnd(_ candidate: RecognitionCandidate) -> Double {
        if candidate.stableUTF16Length == candidate.text.utf16.count { return candidate.audioEndSeconds }
        guard let mapped = try? mappedTokens(candidate) else { return candidate.audioStartSeconds }
        var end = candidate.audioStartSeconds
        for item in mapped {
            if item.end > candidate.stableUTF16Length || !item.token.isFinal { break }
            end = item.token.endSeconds
        }
        return end
    }
    static func latestPerRun(_ candidates: [RecognitionCandidate]) -> [RecognitionCandidate] {
        var results: [UUID: RecognitionCandidate] = [:]
        for candidate in candidates where candidate.sequence > (results[candidate.run.id]?.sequence ?? -1) { results[candidate.run.id] = candidate }
        return results.values.sorted { $0.run.id.uuidString < $1.run.id.uuidString }
    }
    static func previewOrder(_ lhs: RecognitionCandidate, _ rhs: RecognitionCandidate) -> Bool {
        func rank(_ candidate: RecognitionCandidate) -> Int {
            switch candidate.run.purpose { case .audioReview: 0; case .finalASR: 1; case .multilingualASR: 2; case .chineseASR: 3; case .englishASR: 4; case .textFusion: 5 }
        }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        return lhs.createdAt > rhs.createdAt
    }
    static func roleSupports(text: String, run: ModelRunTicket) -> Bool {
        // Expert is a routing responsibility, not a monolingual claim. The registered adapters
        // currently support Chinese/English. Unknown future adapters get conservative role limits.
        let bilingualProviders: Set<String> = ["qwenMessage", "assemblyAI", "soniox", "elevenLabsRealtime", "elevenLabsFile", "openAITranscription", "gemini"]
        if run.purpose != .textFusion && bilingualProviders.contains(run.provider) { return true }
        let purpose = run.purpose
        let hasHan = text.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) || (0x20000...0x3134f).contains($0.value) }
        let hasLatin = text.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
        switch purpose {
        case .chineseASR: return !hasLatin
        case .englishASR: return !hasHan
        case .multilingualASR, .audioReview, .finalASR: return true
        case .textFusion: return false
        }
    }
    static func audioInterval(span: CandidateSpan, candidate: RecognitionCandidate) throws -> (start: Double, end: Double) {
        if span.utf16Start == 0, span.utf16End == candidate.text.utf16.count {
            return (candidate.audioStartSeconds, candidate.audioEndSeconds)
        }
        let mapped = try mappedTokens(candidate)
        var start: Double?, end: Double?
        for (index, item) in mapped.enumerated() {
            let leading = index == 0 ? 0 : mapped[index - 1].end
            let trailing = index + 1 == mapped.count ? candidate.text.utf16.count : mapped[index + 1].start
            if span.utf16Start >= leading && span.utf16Start <= item.start { start = item.token.startSeconds }
            if span.utf16End >= item.end && span.utf16End <= trailing { end = item.token.endSeconds }
        }
        guard let start, let end, end >= start else { throw FusionError.insufficientAlignment }
        return (start, end)
    }
    /// Locate literal token strings in the actual transcript, allowing only intervening layout.
    /// This preserves providers whose words omit spaces without inventing any acoustic timing.
    static func mappedTokens(_ candidate: RecognitionCandidate) throws -> [(token: RecognitionToken, start: Int, end: Int)] {
        guard ["word", "token", "segment"].contains(candidate.timingGranularity), !candidate.tokens.isEmpty else { throw FusionError.insufficientAlignment }
        let source = candidate.text as NSString
        let layout = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var cursor = 0, mapped: [(token: RecognitionToken, start: Int, end: Int)] = []
        for token in candidate.tokens where !token.text.isEmpty {
            let range = source.range(of: token.text, options: .literal, range: NSRange(location: cursor, length: source.length - cursor))
            guard range.location != NSNotFound else { throw FusionError.insufficientAlignment }
            let gap = source.substring(with: NSRange(location: cursor, length: range.location - cursor))
            guard gap.unicodeScalars.allSatisfy({ layout.contains($0) }) else { throw FusionError.insufficientAlignment }
            mapped.append((token, range.location, NSMaxRange(range))); cursor = NSMaxRange(range)
        }
        let tail = source.substring(from: cursor)
        guard !mapped.isEmpty, tail.unicodeScalars.allSatisfy({ layout.contains($0) }) else { throw FusionError.insufficientAlignment }
        return mapped
    }
    static func corroborated(value: String, candidate: RecognitionCandidate,
                             interval: (start: Double, end: Double), candidates: [RecognitionCandidate]) -> Bool {
        candidates.contains { other in
            other.run.provider + ":" + other.run.model != candidate.run.provider + ":" + candidate.run.model &&
            other.text == value && abs(other.audioStartSeconds - interval.start) < 0.08 &&
            abs(other.audioEndSeconds - interval.end) < 0.08 && roleSupports(text: value, run: other.run)
        }
    }
    static func completeLexicalPrefix(_ text: String) -> String {
        var result = text
        // Never publish the shared beginning of two different numeric/Latin words (12/13,
        // do/don't). Chinese characters remain complete graphemes, not invented word boundaries.
        let unsafe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:/%％+-'’零〇一二三四五六七八九十百千万亿两")
        while let character = result.last, character.unicodeScalars.allSatisfy({ unsafe.contains($0) }) { result.removeLast() }
        return result
    }
    /// A rejection guard, not a semantic understanding claim. Unknown conflicts still remain
    /// candidates for explicit acoustic review. Preserve the ordered critical tokens verbatim.
    static func protectedSignature(_ text: String) -> String {
        let pattern = #"(?i)(\b[\p{L}]+\b)(?:[\s,，]+\1\b)+|([\x{3400}-\x{9fff}])\2+|[+-]?[0-9]+(?:[.,:/-][0-9]+)*(?:%|％)?|[零〇一二三四五六七八九十百千万亿两]+|不|没|无|未|别|非|否|勿|\b(?:no|not|never|neither|nor|without|cannot|can't|don't|doesn't|didn't|isn't|aren't|wasn't|weren't|won't|wouldn't|shouldn't|couldn't)\b|[¥￥$€£]|\b(?:kg|mg|g|km|cm|mm|ms|usd|rmb|hours?|minutes?|seconds?|percent|dollars?)\b|公斤|千克|毫克|毫升|公里|厘米|毫米|元|万元|亿元|秒|分钟|小时|年|月|日|点"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range).lowercased() }.joined(separator: "\u{1f}")
    }
}
