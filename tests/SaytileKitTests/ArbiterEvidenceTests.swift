import Foundation
import Testing
@testable import SaytileKit

@Suite("Arbiter evidence and blind acoustic review")
struct ArbiterEvidenceTests {
    private func candidate(_ text: String, purpose: RecognitionPurpose = .chineseASR,
                           tokens: [RecognitionToken] = [], granularity: String = "utterance",
                           complete: Bool = true, end: Double = 3,
                           recognitionID: UUID = UUID(), recordingID: UUID = UUID()) -> RecognitionCandidate {
        let run = ModelRunTicket(recognitionID: recognitionID, recordingID: recordingID, audioEpoch: 0,
            configurationID: UUID(), provider: purpose.rawValue, model: "fixture", purpose: purpose)
        return RecognitionCandidate(run: run, sequence: 7, text: text, stableUTF16Length: text.utf16.count,
            audioEndSeconds: end, timingGranularity: granularity, isComplete: complete, tokens: tokens)
    }
    private func requestPayload(_ evidence: [ReviewEvidence], prefix: String = "") throws -> [String: Any] {
        let data = try PrecisionReviewClient.requestBody(evidence: evidence, confirmedPrefix: prefix,
            context: "", configuration: .init(purpose: .textFusion, provider: .openAIResponses, model: "fixture"))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try #require(root["input"] as? [[String: Any]])
        let content = try #require(input.first?["content"] as? String)
        return try #require(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
    }
    private func response(_ decision: PrecisionReviewDecision, extra: [[String: Any]] = [], messageStatus: String = "completed") throws -> Data {
        let value = try #require(String(data: JSONEncoder().encode(decision), encoding: .utf8))
        return try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [
            ["type": "message", "status": messageStatus,
             "content": [["type": "output_text", "text": value]] + extra]]])
    }
    private func validate(_ decision: PrecisionReviewDecision, candidates: [RecognitionCandidate]) throws -> FusionProposal {
        try PrecisionFusion.validateSelection(spans: decision.selections.map {
            CandidateSpan(candidateID: $0.candidateID, utf16Start: $0.utf16Start, utf16End: $0.utf16End)
        }, candidates: candidates, unresolved: decision.unresolved, needsAudioReview: decision.needsAudioReview)
    }

    @Test func completeProvenanceAndAllTokensReachArbiter() throws {
        let tokens = (0..<300).map { i in RecognitionToken(text: "word\(i) ", startSeconds: Double(i) / 100,
            endSeconds: Double(i + 1) / 100, isFinal: i < 299) }
        let source = candidate(tokens.map(\.text).joined(), tokens: tokens, granularity: "word", complete: false)
        let payload = try requestPayload([ReviewEvidence(candidate: source)])
        let sources = try #require(payload["candidates"] as? [[String: Any]])
        let sent = try #require(sources.first)
        #expect(sent["isComplete"] as? Bool == false)
        #expect(sent["runID"] as? String == source.run.id.uuidString)
        #expect(sent["configurationID"] as? String == source.run.configurationID.uuidString)
        #expect(sent["sequence"] as? Int == 7)
        #expect((sent["tokens"] as? [[String: Any]])?.count == 300)
        let boundaries = try #require(payload["boundaries"] as? [[String: Any]])
        let aligned = try #require(boundaries.first?["alignedTokens"] as? [[String: Any]])
        #expect(aligned.count == 300)
        #expect(aligned.last?["text"] as? String == "word299 ")
        #expect(aligned.last?["isFinal"] as? Bool == false)
        #expect(aligned.last?["end"] as? Int == source.text.utf16.count)
    }

    @Test func utteranceUnicodeBoundariesNeverBecomeInventedWordTimes() throws {
        let source = candidate("不要删😀，测试")
        let evidence = ReviewEvidence(candidate: source)
        let payload = try requestPayload([evidence])
        let boundaries = try #require(payload["boundaries"] as? [[String: Any]])
        #expect(boundaries.first?["wholeCandidateOnly"] as? Bool == true)
        #expect((boundaries.first?["alignedTokens"] as? [[String: Any]])?.isEmpty == true)
        let split = PrecisionReviewDecision(selections: [.init(candidateID: source.id, utf16Start: 0, utf16End: 3)],
            unresolved: false, needsAudioReview: false, reasonCode: "fixture")
        #expect(throws: Error.self) { try validate(split, candidates: [source]) }
        let whole = PrecisionReviewDecision(selections: [.init(candidateID: source.id, utf16Start: 0, utf16End: source.text.utf16.count)],
            unresolved: false, needsAudioReview: false, reasonCode: "fixture")
        #expect(try validate(whole, candidates: [source]).stableText == source.text)
    }

    @Test func actualTimedChineseEnglishPartsCanComposeOneUtterance() throws {
        let generation = UUID(), recording = UUID()
        let prefix = "请用 ", suffix = " 编写测试", zhTerm = "斯威夫特", enTerm = "Swift"
        func tokens(_ term: String) -> [RecognitionToken] { [
            .init(text: prefix, startSeconds: 0, endSeconds: 1, isFinal: true),
            .init(text: term, startSeconds: 1, endSeconds: 2, isFinal: true),
            .init(text: suffix, startSeconds: 2, endSeconds: 3, isFinal: true)] }
        let zh = candidate(prefix + zhTerm + suffix, tokens: tokens(zhTerm), granularity: "segment",
            recognitionID: generation, recordingID: recording)
        let en = candidate(prefix + enTerm + suffix, purpose: .englishASR, tokens: tokens(enTerm), granularity: "segment",
            recognitionID: generation, recordingID: recording)
        let selections: [ReviewSelection] = [
            .init(candidateID: zh.id, utf16Start: 0, utf16End: prefix.utf16.count),
            .init(candidateID: en.id, utf16Start: prefix.utf16.count, utf16End: (prefix + enTerm).utf16.count),
            .init(candidateID: zh.id, utf16Start: (prefix + zhTerm).utf16.count, utf16End: zh.text.utf16.count)]
        let decision = PrecisionReviewDecision(selections: selections, unresolved: false, needsAudioReview: false, reasonCode: "source-composition")
        let decoded = try PrecisionReviewClient.decodeResponse(response(decision)).0
        let proposal = try validate(decoded, candidates: [zh, en])
        #expect(proposal.previewText == prefix + enTerm + suffix)
        #expect(proposal.stableText == proposal.previewText)
        #expect(!proposal.unresolved)
    }

    @Test func arbiterConfidenceCannotOverrideNumberOrNegationDisagreement() throws {
        let generation = UUID(), recording = UUID()
        for (a, b) in [("不要支付100元", "支付100元"), ("支付100元", "支付1000元")] {
            let first = candidate(a, recognitionID: generation, recordingID: recording)
            let second = candidate(b, purpose: .multilingualASR, recognitionID: generation, recordingID: recording)
            let decision = PrecisionReviewDecision(selections: [.init(candidateID: first.id, utf16Start: 0, utf16End: first.text.utf16.count)],
                unresolved: false, needsAudioReview: false, reasonCode: "confident")
            let decoded = try PrecisionReviewClient.decodeResponse(response(decision)).0
            let result = try PrecisionFusion.validateSelection(spans: decoded.selections.map {
                CandidateSpan(candidateID: $0.candidateID, utf16Start: $0.utf16Start, utf16End: $0.utf16End)
            }, candidates: [first, second])
            #expect(result.needsAudioReview)
            #expect(result.stableText.isEmpty)
        }
    }

    @Test func malformedSourceIdentityAndUnicodeEvidenceFailBeforeRequest() throws {
        let source = candidate("😀测试")
        let evidence = ReviewEvidence(candidate: source)
        #expect(throws: Error.self) { try requestPayload([evidence, evidence]) }
        let broken = ReviewEvidence(candidateID: UUID(), provider: "fixture", model: "fixture", role: "chineseASR",
            text: source.text, stableUTF16Length: 1, audioStartSeconds: 0, audioEndSeconds: 1, timingGranularity: "utterance")
        #expect(throws: Error.self) { try requestPayload([broken]) }
        for selection in [ReviewSelection(candidateID: UUID(), utf16Start: 0, utf16End: 2),
                          ReviewSelection(candidateID: source.id, utf16Start: 0, utf16End: 1),
                          ReviewSelection(candidateID: source.id, utf16Start: -1, utf16End: 2)] {
            #expect(throws: Error.self) {
                try validate(.init(selections: [selection], unresolved: false,
                    needsAudioReview: false, reasonCode: "fixture"), candidates: [source])
            }
        }
    }

    @Test func abstentionAndRefusalCannotMasqueradeAsConfirmedText() throws {
        let empty = PrecisionReviewDecision(selections: [], unresolved: true, needsAudioReview: true, reasonCode: "insufficient-evidence")
        #expect(try PrecisionReviewClient.decodeResponse(response(empty)).0 == empty)
        let refusal = try response(empty, extra: [["type": "refusal", "refusal": "fixture"]])
        #expect(throws: Error.self) { try PrecisionReviewClient.decodeResponse(refusal) }
        let partial = try response(empty, messageStatus: "incomplete")
        #expect(throws: Error.self) { try PrecisionReviewClient.decodeResponse(partial) }
    }

    @Test func externalPrefixIsAConstraintAndNeverAnAcousticVote() throws {
        let payload = try requestPayload([ReviewEvidence(candidate: candidate("不要支付100元"))], prefix: "支付100元")
        #expect(payload["externallyReservedPrefix"] as? String == "支付100元")
        #expect(payload["confirmedPrefix"] == nil)
        #expect(PrecisionReviewClient.instructions.contains("including corrections before externallyReservedPrefix"))
        #expect(PrecisionReviewClient.instructions.contains("not solely because a correction differs"))
    }

    @Test func blindAudioReviewUsesOnlyFixedInstructionsAndExactPCM() throws {
        let pcm = Data([1, 0, 2, 0, 3, 0])
        let config = ModelConfiguration(purpose: .audioReview, provider: .gemini, model: "fixture", cloudConsent: true,
            context: "PRIVATE_CANDIDATE_SUGGESTION")
        let request = try PrecisionReviewClient.audioRequest(pcm: pcm, configuration: config, credential: "fixture-key")
        let body = try #require(request.httpBody)
        #expect(!String(decoding: body, as: UTF8.self).contains(config.context))
        let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let contents = try #require(root["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let audio = try #require(parts.last?["inline_data"] as? [String: Any])
        let encoded = try #require(audio["data"] as? String)
        #expect(Data(base64Encoded: encoded) == PCMJournal.header(frames: 3) + pcm)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "fixture-key")
    }

    @Test func blindAudioRequestRejectsConsentPurposeCredentialAndRegionMismatch() {
        let pcm = Data([0, 0])
        var config = ModelConfiguration(purpose: .audioReview, provider: .gemini, model: "fixture")
        #expect(throws: Error.self) { try PrecisionReviewClient.audioRequest(pcm: pcm, configuration: config, credential: "fixture") }
        config.cloudConsent = true
        #expect(throws: Error.self) { try PrecisionReviewClient.audioRequest(pcm: pcm, configuration: config, credential: "") }
        config.purpose = .textFusion
        #expect(throws: Error.self) { try PrecisionReviewClient.audioRequest(pcm: pcm, configuration: config, credential: "fixture") }
        config.purpose = .audioReview; config.region = "unsupported"
        #expect(throws: Error.self) { try PrecisionReviewClient.audioRequest(pcm: pcm, configuration: config, credential: "fixture") }
    }

    @Test func uncertainAudioAndHiddenReasoningRemainDistinct() throws {
        let transcript = AudioReviewTranscript(text: "不要支付100元", uncertain: true)
        let encoded = try #require(String(data: JSONEncoder().encode(transcript), encoding: .utf8))
        let data = try JSONSerialization.data(withJSONObject: ["candidates": [["finishReason": "STOP", "content": ["parts": [
            ["text": "not transcript", "thought": true], ["text": encoded]]]]],
            "usageMetadata": ["promptTokenCount": 10, "candidatesTokenCount": 11, "thoughtsTokenCount": 12]])
        let (result, _, input, output) = try PrecisionReviewClient.decodeAudioResponse(data)
        #expect(result == transcript)
        #expect(input == 10)
        #expect(output == 23)
        let incomplete = Data(#"{"candidates":[{"finishReason":"MAX_TOKENS","content":{"parts":[{"text":"{}"}]}}]}"#.utf8)
        #expect(throws: Error.self) { try PrecisionReviewClient.decodeAudioResponse(incomplete) }
    }

    @Test func finalASRRejectsWordTimesOutsideActualUploadedAudio() throws {
        let payload = Data(#"{"text":"test","words":[{"text":"test","start":0,"end":9}]}"#.utf8)
        #expect(throws: Error.self) { try FinalASRProvider.parse(payload, provider: .elevenLabsFile, duration: 1, requestID: nil) }
        #expect(throws: Error.self) { try FinalASRProvider.parse(payload, provider: .elevenLabsFile, duration: .infinity, requestID: nil) }
        let correct = try FinalASRProvider.parse(payload, provider: .elevenLabsFile, duration: 9, requestID: nil)
        #expect(correct.timingGranularity == "word")
        #expect(correct.audioEndSeconds == 9)
        #expect(correct.isComplete)
    }
}
