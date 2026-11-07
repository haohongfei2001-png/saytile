import Foundation
import Testing
@testable import SaytileKit

/// Deliberately different full sentences, not copied agreement-only fixtures.
/// All audio/evidence is authored data; these tests never contact an ASR service.
private struct PublicationEvidence {
    let recordingID = UUID()
    let recognitionID = UUID()
    func candidate(_ text: String, purpose: RecognitionPurpose = .chineseASR,
                   configurationID: UUID = UUID(), end: Double = 2,
                   stable: Int? = nil, complete: Bool = true) -> RecognitionCandidate {
        let run = ModelRunTicket(recognitionID: recognitionID, recordingID: recordingID, audioEpoch: 1,
            configurationID: configurationID, provider: purpose == .chineseASR ? "qwenMessage" : "assemblyAI",
            model: "authored-publication-fixture", purpose: purpose)
        return RecognitionCandidate(run: run, sequence: 1, text: text,
            stableUTF16Length: stable ?? text.utf16.count, audioEndSeconds: end,
            timingGranularity: "utterance", isComplete: complete)
    }
}
private func entire(_ candidate: RecognitionCandidate) -> CandidateSpan {
    CandidateSpan(candidateID: candidate.id, utf16Start: 0, utf16End: candidate.text.utf16.count)
}

@Suite("Evidence-constrained fusion publication")
struct FusionPublicationTests {
    @Test func emptyCommonPrefixWaitsThenWholeSentenceSelectionActuallyPublishes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-fusion-publication-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let record = try await store.createRecording()
        let ticket = try await store.beginFusionRecognition(recordingID: record.id)
        var candidates: [RecognitionCandidate] = []
        for (purpose, provider, text) in [
            (RecognitionPurpose.chineseASR, CloudProvider.qwenMessage, "使用 SwiftUI 构建界面。"),
            (.englishASR, .assemblyAI, "Build the interface with SwiftUI.")
        ] {
            let run = try await store.beginModelRun(ticket: ticket, configuration:
                ModelConfiguration(purpose: purpose, provider: provider, model: "authored-fixture"))
            let candidate = RecognitionCandidate(run: run, sequence: 1, text: text,
                stableUTF16Length: text.utf16.count, audioEndSeconds: 2, isComplete: true)
            #expect(try await store.appendRecognitionCandidate(candidate))
            candidates.append(candidate)
        }
        let initial = PrecisionFusion.evaluate(candidates: candidates, mode: .highestQuality)
        #expect(initial.stableText.isEmpty)
        #expect(initial.unresolved)
        let deferred = try await store.publishFusion(ticket: ticket, proposal: initial)
        #expect(!deferred.published)
        #expect(try await store.latestDispatchableRevision(recordingID: record.id) == nil)
        let selected = try PrecisionFusion.validateSelection(spans: [entire(candidates[1])], candidates: candidates)
        #expect(selected.stableText == candidates[1].text)
        #expect(!selected.unresolved)
        let publication = try await store.publishFusion(ticket: ticket, proposal: selected)
        #expect(publication.published)
        #expect(publication.revision?.text == candidates[1].text)
        #expect(try await store.latestDispatchableRevision(recordingID: record.id)?.text == candidates[1].text)
        #expect(try await store.recognitionCandidates(recordingID: record.id).count == 2)
        try await store.close()
    }

    @Test func utteranceOnlyAllowsWholeSelectionButNeverCharacterSplicing() throws {
        let evidence = PublicationEvidence()
        let zh = evidence.candidate("使用swift UI构建界面")
        let en = evidence.candidate("使用SwiftUI构建界面", purpose: .englishASR)
        let whole = try PrecisionFusion.validateSelection(spans: [entire(en)], candidates: [zh, en])
        #expect(whole.stableText == en.text)
        #expect(throws: FusionError.self) {
            try PrecisionFusion.validateSelection(spans: [
                .init(candidateID: zh.id, utf16Start: 0, utf16End: 2),
                .init(candidateID: en.id, utf16Start: 2, utf16End: en.text.utf16.count)
            ], candidates: [zh, en])
        }
        #expect(throws: FusionError.self) {
            try PrecisionFusion.validateSelection(spans: [entire(zh), entire(en)], candidates: [zh, en])
        }
    }

    @Test func wholeUtteranceSelectionStillCannotResolveUnsupportedNegation() throws {
        let evidence = PublicationEvidence()
        let zh = evidence.candidate("不要发送草稿")
        let en = evidence.candidate("发送草稿", purpose: .englishASR)
        let proposal = try PrecisionFusion.validateSelection(spans: [entire(en)], candidates: [zh, en])
        #expect(proposal.stableText.isEmpty)
        #expect(proposal.needsAudioReview)
        #expect(proposal.unresolved)
    }

    @Test func completeShortReviewDoesNotDeclareLongerLiveUtteranceResolved() throws {
        let evidence = PublicationEvidence()
        let review = evidence.candidate("去公园", purpose: .audioReview, end: 2)
        let zh = evidence.candidate("去公园然后回家", end: 5)
        let en = evidence.candidate("去公园然后回家", purpose: .englishASR, end: 5)
        let proposal = try PrecisionFusion.validateSelection(spans: [entire(review)], candidates: [zh, en, review])
        // The reviewed prefix remains usable; the later words still need their own decision.
        #expect(proposal.stableText == review.text)
        #expect(proposal.unresolved)
        #expect(!proposal.needsAudioReview)
    }

    @Test func longerSilentCoverageDoesNotInventAnUnresolvedTextTail() throws {
        let evidence = PublicationEvidence()
        let short = evidence.candidate("去公园", end: 2)
        let long = evidence.candidate("去公园", purpose: .englishASR, end: 5)
        let proposal = try PrecisionFusion.validateSelection(spans: [entire(short)], candidates: [short, long])
        #expect(proposal.stableText == short.text)
        #expect(!proposal.unresolved)
    }

    @Test func missingSecondExpertWithTheSamePurposeCannotCountAsFullCoverage() {
        let evidence = PublicationEvidence(), delayedID = UUID()
        let zh = evidence.candidate("保留完整原话"), en = evidence.candidate("保留完整原话", purpose: .englishASR)
        let required = Set([zh.run.configurationID, en.run.configurationID, delayedID])
        let held = PrecisionFusion.evaluate(candidates: [zh, en], mode: .highestQuality,
            requiredConfigurationIDs: required)
        #expect(held.stableText.isEmpty)
        #expect(held.previewText == zh.text)
        #expect(held.unresolved)
        #expect(held.reasonCode == "waiting-all-enabled-experts")
        // The delayed or failed model contributes no vote until actual evidence arrives.
        let partial = evidence.candidate(zh.text, configurationID: delayedID, stable: 0, complete: false)
        let awaitingStability = PrecisionFusion.evaluate(candidates: [zh, en, partial], mode: .highestQuality,
            requiredConfigurationIDs: required)
        #expect(awaitingStability.stableText.isEmpty)
        #expect(awaitingStability.unresolved)
        let completed = evidence.candidate(zh.text, configurationID: delayedID)
        let ready = PrecisionFusion.evaluate(candidates: [zh, en, completed], mode: .highestQuality,
            requiredConfigurationIDs: required)
        #expect(ready.stableText == zh.text)
        #expect(!ready.unresolved)
    }

    @Test func requiredExpertFromAnotherGenerationCannotSatisfyEvidenceCoverage() {
        let evidence = PublicationEvidence(), foreign = PublicationEvidence(), missingID = UUID()
        let zh = evidence.candidate("保留原话"), en = evidence.candidate("保留原话", purpose: .englishASR)
        let unrelated = foreign.candidate(zh.text, configurationID: missingID)
        let result = PrecisionFusion.evaluate(candidates: [zh, en, unrelated], mode: .highestQuality,
            requiredConfigurationIDs: [zh.run.configurationID, en.run.configurationID, missingID])
        #expect(result.stableText.isEmpty)
        #expect(result.unresolved)
    }

    @Test func absentRequiredExpertNeverErasesAnAlreadyDispatchedPrefix() {
        let evidence = PublicationEvidence(), missingID = UUID()
        let zh = evidence.candidate("已发文字和后文"), en = evidence.candidate("已发文字和后文", purpose: .englishASR)
        let result = PrecisionFusion.evaluate(candidates: [zh, en], mode: .highestQuality,
            committedPrefix: "已发文字", requiredConfigurationIDs: [zh.run.configurationID, en.run.configurationID, missingID])
        #expect(result.stableText == "已发文字")
        #expect(result.unresolved)
    }

    @Test func englishNumberWordsAndCurrencyAreProtectedWithoutRewritingSourceText() {
        func signature(_ value: String) -> String { PrecisionFusion.protectedSignature(value) }
        #expect(signature("fifteen dollars") != signature("fifty dollars"))
        #expect(signature("thirteen milligrams") != signature("thirty milligrams"))
        #expect(signature("point five") != signature("five"))
        #expect(signature("first result") != signature("third result"))
        #expect(signature("fifteen dollars") == signature("$15"))
        #expect(signature("$15.50") == signature("15.50 dollars"))
    }

    @Test func fullyStableMetaTurnStillCannotTurnProcessingProgressIntoAcousticCoverage() throws {
        let run = ModelRunTicket(recognitionID: UUID(), recordingID: UUID(), audioEpoch: 1,
            configurationID: UUID(), provider: "meta", model: "authored-fixture", purpose: .englishASR)
        let token = RecognitionToken(text: "hello", startSeconds: 0, endSeconds: 0.8, isFinal: true)
        let inFlight = RecognitionCandidate(run: run, sequence: 1, text: "hello", stableUTF16Length: 5,
            audioEndSeconds: 1.7, timingGranularity: "turn-progress", isComplete: false, tokens: [token])
        #expect(PrecisionFusion.reviewRetirementHorizon(inFlight) == 0.8)
        #expect(PrecisionFusion.stableAudioEnd(inFlight) == 0)
        #expect(PrecisionFusion.evidencePrefix(inFlight, through: 2) == nil)
        #expect(throws: FusionError.self) {
            try PrecisionFusion.validateSelection(spans: [entire(inFlight)], candidates: [inFlight])
        }
        // Literal stable agreement needs no inferred acoustic boundary.
        #expect(PrecisionFusion.evaluate(candidates: [inFlight], mode: .fast).stableText == "hello")
        // Meta's acknowledged completedEvent replaces progress with the actual sent PCM duration.
        let complete = RecognitionCandidate(run: run, sequence: 2, text: "hello", stableUTF16Length: 5,
            audioEndSeconds: 2, timingGranularity: "turn-progress", isComplete: true, tokens: [token])
        #expect(PrecisionFusion.stableAudioEnd(complete) == 2)
        let selected = try PrecisionFusion.validateSelection(spans: [entire(complete)], candidates: [complete])
        #expect(selected.stableText == "hello")
        #expect(!selected.unresolved)
    }
}
