import Foundation
import Testing
@testable import SaytileKit

private struct MultiFixture {
    let directory: URL
    let store: SaytileStore
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-multi-test-" + UUID().uuidString)
        store = try SaytileStore(directory: directory)
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    func record(date: Date = Date()) async throws -> Recording {
        let record = try await store.createRecording(createdAt: date)
        let path = record.id.uuidString + "/chunk.wav"
        let file = store.audioDirectory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 32044).write(to: file)
        try await store.registerAudioChunk(recordingID: record.id, relativePath: path, frames: 16000)
        try await store.finishRecording(id: record.id)
        return record
    }
    func run(_ ticket: RecognitionTicket, _ purpose: RecognitionPurpose) async throws -> ModelRunTicket {
        try await store.beginModelRun(ticket: ticket, configuration: ModelConfiguration(purpose: purpose,
            provider: purpose == .chineseASR ? .qwenMessage : .assemblyAI, model: "test-model"))
    }
    func pair(_ ticket: RecognitionTicket, _ text: String) async throws -> [RecognitionCandidate] {
        let zh = try await run(ticket, .chineseASR), en = try await run(ticket, .englishASR)
        let candidates = [sample(text, run: zh), sample(text, run: en)]
        for candidate in candidates { #expect(try await store.appendRecognitionCandidate(candidate)) }
        return candidates
    }
}
private let sampleRecordingID = UUID()
private let sampleRecognitionID = UUID()

private func sample(_ text: String, purpose: RecognitionPurpose = .chineseASR,
                    run: ModelRunTicket? = nil, sequence: Int64 = 0, stable: Int? = nil,
                    start: Double = 0, end: Double = 2, granularity: String = "utterance",
                    tokens: [RecognitionToken] = []) -> RecognitionCandidate {
    let ticket = run ?? ModelRunTicket(recognitionID: sampleRecognitionID, recordingID: sampleRecordingID, audioEpoch: 1,
        configurationID: UUID(), provider: purpose == .chineseASR ? "qwenMessage" : "assemblyAI", model: "test-model", purpose: purpose)
    return RecognitionCandidate(run: ticket, sequence: sequence, text: text, stableUTF16Length: stable ?? text.utf16.count,
        audioStartSeconds: start, audioEndSeconds: end, timingGranularity: granularity, isComplete: true, tokens: tokens)
}

@Test func multiCandidatesAreIsolatedAndLegacyCannotPublishFusionTicket() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let candidates = try await f.pair(ticket, "你好 SwiftUI")
    #expect(try await f.store.revisions(recordingID: record.id).isEmpty)
    #expect(try await !f.store.applyRecognition(ticket: ticket, text: "adapter bypass", isFinal: true))
    let proposal = PrecisionFusion.evaluate(candidates: candidates, mode: .highestQuality)
    let publication = try await f.store.publishFusion(ticket: ticket, proposal: proposal)
    #expect(publication.published)
    #expect(try await f.store.latestDispatchableRevision(recordingID: record.id)?.text == "你好 SwiftUI")
    #expect(try await f.store.fusionDecisions(recordingID: record.id).count == 1)
}

@Test func multiRunSequenceGenerationAndForgedIdentityAreRejected() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let run = try await f.run(ticket, .chineseASR)
    #expect(try await f.store.appendRecognitionCandidate(sample("新", run: run, sequence: 2)))
    #expect(try await !f.store.appendRecognitionCandidate(sample("旧", run: run, sequence: 1)))
    #expect(try await !f.store.appendRecognitionCandidate(sample("重复", run: run, sequence: 2)))
    let forged = ModelRunTicket(id: run.id, recognitionID: run.recognitionID, recordingID: run.recordingID,
        audioEpoch: run.audioEpoch, configurationID: run.configurationID, provider: "forged", model: run.model, purpose: run.purpose)
    #expect(try await !f.store.appendRecognitionCandidate(sample("伪造", run: forged, sequence: 3)))
    _ = try await f.store.beginFusionRecognition(recordingID: record.id)
    #expect(try await !f.store.isRecognitionCurrent(ticket: ticket))
    #expect(try await !f.store.appendRecognitionCandidate(sample("迟到", run: run, sequence: 4)))
    #expect(try await f.store.recognitionCandidates(recordingID: record.id).map(\.text) == ["新"])
}

@Test func multiRestartRetainsEvidenceAndInvalidatesOldCallbacks() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let candidates = try await f.pair(ticket, "已确认")
    _ = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: candidates, mode: .highestQuality))
    try await f.store.close()
    let reopened = try SaytileStore(directory: f.directory)
    #expect(try await !reopened.isRecognitionCurrent(ticket: ticket))
    #expect(try await !reopened.appendRecognitionCandidate(sample("晚回", run: candidates[0].run, sequence: 1)))
    #expect(try await reopened.recognitionCandidates(recordingID: record.id).count == 2)
    #expect(try await reopened.modelRuns(recordingID: record.id).allSatisfy { $0.state == .interrupted })
    #expect(try await reopened.latestDispatchableRevision(recordingID: record.id)?.text == "已确认")
    #expect(try await reopened.recording(id: record.id)?.recognitionState == .queued)
    try await reopened.close()
}

@Test func multiAudioEpochDeletionPreservesCandidateAndPublicationHistory() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let candidates = try await f.pair(ticket, "保留文本")
    _ = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: candidates, mode: .highestQuality))
    try await f.store.deleteAudio(recordingID: record.id)
    #expect(try await !f.store.isRecognitionCurrent(ticket: ticket))
    #expect(try await !f.store.appendRecognitionCandidate(sample("迟到", run: candidates[0].run, sequence: 1)))
    #expect(try await f.store.recognitionCandidates(recordingID: record.id).count == 2)
    #expect(try await f.store.latestDispatchableRevision(recordingID: record.id)?.text == "保留文本")
}

@Test func multiUserEditAndUnsavedDraftRemainSelected() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let edited = try await f.store.saveEdit(recordingID: record.id, text: "用户稿")
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let candidates = try await f.pair(ticket, "模型稿")
    _ = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: candidates, mode: .highestQuality))
    #expect(try await f.store.recording(id: record.id)?.preferredRevisionID == edited.id)
    let second = try await f.record()
    try await f.store.saveDraft(recordingID: second.id, text: "未保存草稿")
    let next = try await f.store.beginFusionRecognition(recordingID: second.id)
    let nextCandidates = try await f.pair(next, "另一个模型稿")
    _ = try await f.store.publishFusion(ticket: next, proposal: PrecisionFusion.evaluate(candidates: nextCandidates, mode: .highestQuality))
    #expect(try await f.store.loadDraft(recordingID: second.id) == "未保存草稿")
    #expect(try await f.store.recording(id: second.id)?.preferredRevisionID == nil)
}

@Test func multiProviderFinalDoesNotOutraceRequiredExpertOrDisagreement() {
    let first = sample("我不要付款")
    let waiting = PrecisionFusion.evaluate(candidates: [first], mode: .highestQuality)
    #expect(waiting.stableText.isEmpty)
    #expect(waiting.unresolved)
    let second = sample("我要付款", purpose: .englishASR)
    let disagreement = PrecisionFusion.evaluate(candidates: [first, second], mode: .highestQuality)
    #expect(disagreement.stableText == "我")
    #expect(disagreement.unresolved)
    #expect(disagreement.needsAudioReview)
    let required = PrecisionFusion.evaluate(candidates: [first, sample(first.text, purpose: .englishASR)],
        mode: .highestQuality, requiredPurposes: [.chineseASR, .englishASR, .multilingualASR])
    #expect(required.stableText.isEmpty)
}

@Test func multiUTF16UsesGraphemesAndDoesNotCommitPartialNumbers() throws {
    let text = "A👩🏽‍💻e\u{301}中"
    #expect(RecognitionUTF16.slice(text, start: 0, end: 2) == nil)
    #expect(RecognitionUTF16.slice(text, start: 1, end: 3) == nil)
    #expect(RecognitionUTF16.commonPrefix(["👩🏽‍💻你好", "👩🏽‍💻您好"]) == "👩🏽‍💻")
    #expect(RecognitionUTF16.commonPrefix(["e\u{301}", "é"]).isEmpty)
    #expect(!RecognitionUTF16.hasExactPrefix("éx", prefix: "e\u{301}"))
    #expect(throws: FusionError.self) { try PrecisionFusion.validateCandidate(sample(text, stable: 2)) }
    let a = sample("pay 123", purpose: .englishASR), b = sample("pay 124")
    #expect(PrecisionFusion.evaluate(candidates: [a, b], mode: .highestQuality).stableText == "pay ")
}

@Test func multiLateCorrectionIsArchivedWithoutRedispatchAndRetryKeepsOldCursor() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let start = Date().addingTimeInterval(-10)
    let binding = try await f.store.createBinding(label: "test", createdAt: start)
    let record = try await f.record(date: start.addingTimeInterval(1))
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let originals = try await f.pair(ticket, "我想买苹果")
    let first = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: originals, mode: .highestQuality))
    let revision = try #require(first.revision)
    let reservation = try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id,
        revisionID: revision.id, stableUTF16End: revision.text.utf16.count)
    #expect(reservation?.text == "我想买苹果")
    let changed = originals.map { sample("我想买梨子", run: $0.run, sequence: 1) }
    for candidate in changed { try await f.store.appendRecognitionCandidate(candidate) }
    let correction = PrecisionFusion.evaluate(candidates: changed, mode: .highestQuality, committedPrefix: revision.text)
    let deferred = try await f.store.publishFusion(ticket: ticket, proposal: correction)
    #expect(!deferred.published)
    #expect(deferred.deferred)
    #expect(try await f.store.latestDispatchableRevision(recordingID: record.id)?.text == "我想买苹果")
    let archive = try #require(try await f.store.latestFinalRevision(recordingID: record.id))
    #expect(archive.text == "我想买梨子")
    await #expect(throws: StoreError.self) { try await f.store.reserveDispatch(bindingID: binding,
        recordingID: record.id, revisionID: archive.id, stableUTF16End: archive.text.utf16.count) }
    #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id,
        revisionID: revision.id, stableUTF16End: revision.text.utf16.count) == nil)
    let retry = try await f.store.beginFusionRecognition(recordingID: record.id)
    let short = try await f.pair(retry, "我想")
    let retryPublication = try await f.store.publishFusion(ticket: retry, proposal: PrecisionFusion.evaluate(candidates: short, mode: .highestQuality))
    #expect(!retryPublication.published)
    #expect(try await f.store.latestDispatchableRevision(recordingID: record.id)?.id == revision.id)
    #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id,
        revisionID: revision.id, stableUTF16End: revision.text.utf16.count) == nil)
}

@Test func multiLLMCannotGenerateSpliceUnknownTimingOrRemoveProtectedContent() throws {
    let original = sample("不要支付100元", end: 2)
    let alternate = sample("要支付1000元", purpose: .englishASR, end: 2.3)
    let selection = [CandidateSpan(candidateID: alternate.id, utf16Start: 0, utf16End: alternate.text.utf16.count)]
    let decision = try PrecisionFusion.validateSelection(spans: selection, candidates: [original, alternate])
    #expect(decision.stableText.isEmpty)
    #expect(decision.needsAudioReview)
    #expect(throws: FusionError.self) { try PrecisionFusion.validateSelection(spans: [CandidateSpan(candidateID: UUID(), utf16Start: 0, utf16End: 2)], candidates: [original]) }
    #expect(throws: FusionError.self) { try PrecisionFusion.validateSelection(spans: [CandidateSpan(candidateID: original.id, utf16Start: 1, utf16End: original.text.utf16.count)], candidates: [original]) }
    let excerpt = sample("后半句", start: 1, end: 2)
    #expect(throws: FusionError.self) { try PrecisionFusion.validateSelection(spans: [CandidateSpan(candidateID: excerpt.id, utf16Start: 0, utf16End: excerpt.text.utf16.count)], candidates: [excerpt]) }
}

@Test func multiRealTokenAlignmentCanCombineChineseAndEnglishEvidence() throws {
    let zh = sample("我想在swift UI里面", granularity: "segment", tokens: [
        RecognitionToken(text: "我想在", startSeconds: 0, endSeconds: 0.5, isFinal: true),
        RecognitionToken(text: "swift UI", startSeconds: 0.5, endSeconds: 1.5, isFinal: true),
        RecognitionToken(text: "里面", startSeconds: 1.5, endSeconds: 2, isFinal: true)])
    let en = sample("我想在SwiftUI里面", purpose: .englishASR, granularity: "word", tokens: [
        RecognitionToken(text: "我想在", startSeconds: 0, endSeconds: 0.5, isFinal: true),
        RecognitionToken(text: "SwiftUI", startSeconds: 0.5, endSeconds: 1.5, isFinal: true),
        RecognitionToken(text: "里面", startSeconds: 1.5, endSeconds: 2, isFinal: true)])
    let result = try PrecisionFusion.validateSelection(spans: [
        CandidateSpan(candidateID: zh.id, utf16Start: 0, utf16End: 3),
        CandidateSpan(candidateID: en.id, utf16Start: 3, utf16End: 10),
        CandidateSpan(candidateID: zh.id, utf16Start: 11, utf16End: 13)], candidates: [zh, en])
    #expect(result.stableText == "我想在SwiftUI里面")
    #expect(!result.unresolved)
}

@Test func multiNonRetryableProviderDoesNotStopOtherRunAndUsagePersists() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let failed = try await f.run(ticket, .chineseASR), working = try await f.run(ticket, .englishASR)
    try await f.store.finishModelRun(failed, error: "authorization: Bearer secret-key", retryable: false)
    #expect(try await f.store.isRecognitionCurrent(ticket: ticket))
    #expect(try await f.store.appendRecognitionCandidate(sample("still recording", run: working)))
    #expect(try await f.store.modelRuns(recordingID: record.id).first { $0.id == failed.id }?.error == "provider-authorization")
    try await f.store.recordModelUsage(run: working, audioSeconds: 2, inputTokens: nil, outputTokens: nil,
        elapsedSeconds: 1, requestID: "request-1", estimatedCost: nil, currency: "USD")
    try await f.store.failRecognition(ticket: ticket, message: "failed expert")
    #expect(try await f.store.claimRecoveryRecording(now: Date().addingTimeInterval(10_000)) == nil)
    try await f.store.close()
    let reopened = try SaytileStore(directory: f.directory)
    #expect(try await reopened.modelUsage(recordingID: record.id).first?.estimatedCost == nil)
    #expect(try await reopened.modelUsage(recordingID: record.id).first?.elapsedSeconds == 1)
    #expect(try await reopened.claimRecoveryRecording(now: Date().addingTimeInterval(10_000)) == nil)
    try await reopened.resetRecognitionRetry(recordingID: record.id)
    #expect(try await reopened.claimRecoveryRecording(now: Date().addingTimeInterval(10_000))?.id == record.id)
    try await reopened.close()
}

@Test func multiNewGenerationMayCorrectUnsentCompleteVersion() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let old = try await f.store.beginFusionRecognition(recordingID: record.id)
    let before = try await f.pair(old, "我想买苹果")
    _ = try await f.store.publishFusion(ticket: old, proposal: PrecisionFusion.evaluate(candidates: before, mode: .highestQuality))
    let new = try await f.store.beginFusionRecognition(recordingID: record.id)
    let corrected = try await f.pair(new, "我想买梨子")
    let result = try await f.store.publishFusion(ticket: new, proposal: PrecisionFusion.evaluate(candidates: corrected, mode: .highestQuality))
    #expect(result.published)
    #expect(try await f.store.latestDispatchableRevision(recordingID: record.id)?.text == "我想买梨子")
}

@Test func multiVolatilePreviewsRemainBoundedButCandidatesAreAuditable() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let run = try await f.run(ticket, .chineseASR)
    for sequence in 0..<20 {
        let candidate = RecognitionCandidate(run: run, sequence: Int64(sequence), text: "实时 \(sequence)", audioEndSeconds: 1)
        try await f.store.appendRecognitionCandidate(candidate)
        _ = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: [candidate], mode: .highestQuality))
    }
    #expect(try await f.store.revisions(recordingID: record.id).count == 1)
    #expect(try await f.store.revisions(recordingID: record.id).first?.origin == .partial)
    #expect(try await f.store.recognitionCandidates(recordingID: record.id).count == 20)
    #expect(try await f.store.latestDispatchableRevision(recordingID: record.id) == nil)
}

@Test func multiSuccessiveReviewRunsKeepHistoricalEvidenceWithoutCappingLatest() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let config = ModelConfiguration(purpose: .audioReview, provider: .gemini, model: "test-audio")
    let first = try await f.store.beginModelRun(ticket: ticket, configuration: config)
    try await f.store.appendRecognitionCandidate(sample("以前", run: first))
    let second = try await f.store.beginModelRun(ticket: ticket, configuration: config)
    #expect(try await !f.store.appendRecognitionCandidate(sample("迟到以前", run: first, sequence: 1)))
    try await f.store.appendRecognitionCandidate(sample("当前", run: second))
    #expect(try await f.store.latestRecognitionCandidates(ticket: ticket).map(\.text) == ["当前"])
    #expect(try await f.store.recognitionCandidates(recordingID: record.id).count == 2)
}

@Test func multiTextSelectionPreservesIntentionalRepetitionAndSignalsOmittedTail() throws {
    let repeated = sample("我我想去公园"), smooth = sample("我想去公园", purpose: .englishASR)
    let review = try PrecisionFusion.validateSelection(spans: [CandidateSpan(candidateID: smooth.id, utf16Start: 0, utf16End: smooth.text.utf16.count)], candidates: [repeated, smooth])
    #expect(review.needsAudioReview)
    #expect(review.stableText.isEmpty)
    let timed = sample("我想去公园", granularity: "segment", tokens: [
        RecognitionToken(text: "我想", startSeconds: 0, endSeconds: 0.5, isFinal: true),
        RecognitionToken(text: "去公园", startSeconds: 0.5, endSeconds: 2, isFinal: true)])
    let prefix = try PrecisionFusion.validateSelection(spans: [CandidateSpan(candidateID: timed.id, utf16Start: 0, utf16End: 2)], candidates: [timed])
    #expect(prefix.stableText == "我想")
    #expect(prefix.unresolved)
}

@Test func multiUncertainAudioReviewCannotResolveProtectedConflict() throws {
    let a = sample("支付100元"), b = sample("支付1000元", purpose: .englishASR)
    let uncertain = sample("支付100元", purpose: .audioReview, stable: 0)
    let result = try PrecisionFusion.validateSelection(spans: [CandidateSpan(candidateID: a.id, utf16Start: 0, utf16End: a.text.utf16.count)], candidates: [a, b, uncertain])
    #expect(result.needsAudioReview)
    #expect(result.stableText.isEmpty)
}

@Test func multiVerifiedPrefixCanPublishWhileAIReportsRemainingTail() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let run = try await f.run(ticket, .chineseASR)
    let timed = sample("我想去公园", run: run, granularity: "segment", tokens: [
        RecognitionToken(text: "我想", startSeconds: 0, endSeconds: 0.5, isFinal: true),
        RecognitionToken(text: "去公园", startSeconds: 0.5, endSeconds: 2, isFinal: true)])
    try await f.store.appendRecognitionCandidate(timed)
    let english = try await f.run(ticket, .englishASR)
    let corroborating = sample("我想去公园", run: english)
    try await f.store.appendRecognitionCandidate(corroborating)
    let proposal = try PrecisionFusion.validateSelection(spans: [CandidateSpan(candidateID: timed.id, utf16Start: 0, utf16End: 2)], candidates: [timed, corroborating])
    let result = try await f.store.publishFusion(ticket: ticket, proposal: proposal)
    #expect(result.published)
    #expect(result.deferred)
    #expect(result.revision?.text == "我想")
}

@Test func multiStoreDoesNotLetAIBypassAbsentRequiredExpert() async throws {
    let f = try MultiFixture(); defer { f.clean() }
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let run = try await f.run(ticket, .chineseASR)
    let only = sample("只有中文先到", run: run)
    try await f.store.appendRecognitionCandidate(only)
    let proposal = try PrecisionFusion.validateSelection(spans: [CandidateSpan(candidateID: only.id, utf16Start: 0, utf16End: only.text.utf16.count)], candidates: [only])
    await #expect(throws: FusionError.self) { try await f.store.publishFusion(ticket: ticket, proposal: proposal) }
    #expect(try await f.store.latestDispatchableRevision(recordingID: record.id) == nil)
}
