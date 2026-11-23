import Foundation
import Testing
@testable import SaytileKit

private struct RevisionFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-fusion-revision-" + UUID().uuidString)
    let store: SaytileStore
    init() throws { store = try SaytileStore(directory: directory) }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    func record() async throws -> Recording {
        let record = try await store.createRecording()
        let path = record.id.uuidString + "/chunk.wav"
        let url = store.audioDirectory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 32044).write(to: url)
        try await store.registerAudioChunk(recordingID: record.id, relativePath: path, frames: 16000)
        try await store.finishRecording(id: record.id)
        return record
    }
    func pair(_ ticket: RecognitionTicket, _ text: String) async throws -> [RecognitionCandidate] {
        var values: [RecognitionCandidate] = []
        for purpose in [RecognitionPurpose.chineseASR, .englishASR] {
            let config = ModelConfiguration(purpose: purpose, provider: purpose == .chineseASR ? .qwenMessage : .assemblyAI, model: "fixture")
            let run = try await store.beginModelRun(ticket: ticket, configuration: config)
            let candidate = RecognitionCandidate(run: run, sequence: 0, text: text, stableUTF16Length: text.utf16.count, audioEndSeconds: 1, isComplete: true)
            _ = try await store.appendRecognitionCandidate(candidate); values.append(candidate)
        }
        return values
    }
    func correction(_ ticket: RecognitionTicket, _ text: String, evidence: [RecognitionCandidate], prefix: String = "") async throws -> FusionProposal {
        let run = try await store.beginModelRun(ticket: ticket, configuration: .init(purpose: .finalASR, provider: .elevenLabsFile, model: "fixture-final"))
        let candidate = RecognitionCandidate(run: run, sequence: 0, text: text, stableUTF16Length: text.utf16.count, audioEndSeconds: 1, isComplete: true)
        _ = try await store.appendRecognitionCandidate(candidate)
        return try PrecisionFusion.validateSelection(spans: [.init(candidateID: candidate.id, utf16Start: 0, utf16End: text.utf16.count)], candidates: evidence + [candidate], committedPrefix: prefix)
    }
}

@Test func fusionRevisionFinalReviewCanCorrectSameGenerationBeforeAnyDispatch() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let pair = try await f.pair(ticket, "我想买苹果")
    let initial = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: pair, mode: .highestQuality))
    let old = try #require(initial.revision)
    let reviewed = try await f.correction(ticket, "我想买梨子", evidence: pair)
    let updated = try await f.store.publishFusion(ticket: ticket, proposal: reviewed)
    #expect(updated.published)
    #expect(try await f.store.latestDispatchableRevision(recordingID: record.id)?.text == "我想买梨子")
    #expect(try await f.store.revisions(recordingID: record.id).contains { $0.id == old.id && $0.text == "我想买苹果" })
}

@Test func fusionRevisionCanCorrectOnlyUnreservedSuffixAndPreservesDraft() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label: "isolated")
    let record = try await f.record()
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let pair = try await f.pair(ticket, "我想买苹果")
    let initial = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: pair, mode: .highestQuality))
    let old = try #require(initial.revision)
    _ = try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: old.id, stableUTF16End: 3)
    let edit = try await f.store.saveEdit(recordingID: record.id, text: "我的编辑版本")
    try await f.store.saveDraft(recordingID: record.id, text: "尚未提交的草稿")
    let reviewed = try await f.correction(ticket, "我想买梨子", evidence: pair, prefix: "我想买")
    let updated = try await f.store.publishFusion(ticket: ticket, proposal: reviewed)
    #expect(updated.published)
    let head = try #require(try await f.store.latestDispatchableRevision(recordingID: record.id))
    let suffix = try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: head.id, stableUTF16End: head.text.utf16.count)
    #expect(suffix?.text == "梨子")
    #expect(try await f.store.recording(id: record.id)?.preferredRevisionID == edit.id)
    #expect(try await f.store.loadDraft(recordingID: record.id) == "尚未提交的草稿")
}

@Test func fusionRevisionSupersededUnreservedFinalCannotStillBeDispatched() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label: "isolated")
    let record = try await f.record(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let pair = try await f.pair(ticket, "我想买苹果")
    let old = try #require(try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: pair, mode: .highestQuality)).revision)
    let reviewed = try await f.correction(ticket, "我想买梨子", evidence: pair)
    _ = try await f.store.publishFusion(ticket: ticket, proposal: reviewed)
    await #expect(throws: StoreError.self) {
        try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: old.id, stableUTF16End: old.text.utf16.count)
    }
    #expect(try await f.store.fusionReservedPrefix(recordingID: record.id).isEmpty)
}

@Test func fusionRevisionChangedEvidenceWaitsWithoutConsumingCursorThenResumes() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label: "isolated")
    let record = try await f.record(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let pair = try await f.pair(ticket, "我想去公园")
    let old = try #require(try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: pair, mode: .highestQuality)).revision)
    let updated = RecognitionCandidate(run: pair[0].run, sequence: 1, text: pair[0].text,
        stableUTF16Length: pair[0].text.utf16.count, audioEndSeconds: 1, isComplete: true)
    #expect(try await f.store.appendRecognitionCandidate(updated))
    // The provider callback persisted, but the coordinator has not evaluated it yet.
    #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id,
        revisionID: old.id, stableUTF16End: old.text.utf16.count) == nil)
    #expect(try await f.store.fusionReservedPrefix(recordingID: record.id).isEmpty)
    let current = [updated, pair[1]]
    let republished = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: current, mode: .highestQuality))
    #expect(!republished.published) // Same words; refresh only the evidence proof.
    let resumed = try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id,
        revisionID: old.id, stableUTF16End: old.text.utf16.count)
    #expect(resumed?.text == old.text)
}

@Test func fusionRevisionLaterEmptyAgreementRevokesEveryUnreservedFinal() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label: "isolated")
    let record = try await f.record(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let pair = try await f.pair(ticket, "上海天气晴")
    let old = try #require(try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: pair, mode: .highestQuality)).revision)
    let changed = RecognitionCandidate(run: pair[1].run, sequence: 1, text: "北京正在下雨",
        stableUTF16Length: 6, audioEndSeconds: 1, isComplete: true)
    #expect(try await f.store.appendRecognitionCandidate(changed))
    let proposal = PrecisionFusion.evaluate(candidates: [pair[0], changed], mode: .highestQuality)
    #expect(proposal.stableText.isEmpty)
    _ = try await f.store.publishFusion(ticket: ticket, proposal: proposal)
    #expect(try await f.store.latestDispatchableRevision(recordingID: record.id) == nil)
    #expect(try await f.store.directInputCandidates(bindingID: binding, createdSince: .distantPast).isEmpty)
    await #expect(throws: StoreError.self) {
        try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: old.id, stableUTF16End: old.text.utf16.count)
    }
    #expect(try await f.store.revisions(recordingID: record.id).contains { $0.id == old.id && $0.text == old.text })
}

@Test func fusionRevisionReservationArrivingDuringReviewKeepsExternalPrefixImmutable() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label: "isolated")
    let record = try await f.record(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let pair = try await f.pair(ticket, "我想买苹果")
    let old = try #require(try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: pair, mode: .highestQuality)).revision)
    // Prepare review evidence before reserving; publish must re-read cursors in its transaction.
    let reviewRun = try await f.store.beginModelRun(ticket: ticket, configuration: .init(purpose: .finalASR, provider: .elevenLabsFile, model: "fixture-final"))
    _ = try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: old.id, stableUTF16End: old.text.utf16.count)
    let evidence = RecognitionCandidate(run: reviewRun, sequence: 0, text: "我想买梨子", stableUTF16Length: 5, audioEndSeconds: 1, isComplete: true)
    #expect(try await f.store.appendRecognitionCandidate(evidence))
    let review = try PrecisionFusion.validateSelection(spans: [.init(candidateID: evidence.id, utf16Start: 0, utf16End: 5)], candidates: pair + [evidence])
    let result = try await f.store.publishFusion(ticket: ticket, proposal: review)
    #expect(!result.published)
    #expect(result.deferred)
    #expect(try await f.store.latestDispatchableRevision(recordingID: record.id)?.id == old.id)
    #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: old.id, stableUTF16End: old.text.utf16.count) == nil)
}

@Test func fusionRevisionLongestCompatibleBindingPrefixProtectsEveryTarget() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let first = try await f.store.createBinding(label: "first"), second = try await f.store.createBinding(label: "second")
    let record = try await f.record(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let pair = try await f.pair(ticket, "我想买苹果")
    let old = try #require(try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: pair, mode: .highestQuality)).revision)
    _ = try await f.store.reserveDispatch(bindingID: first, recordingID: record.id, revisionID: old.id, stableUTF16End: 3)
    _ = try await f.store.reserveDispatch(bindingID: second, recordingID: record.id, revisionID: old.id, stableUTF16End: 4)
    #expect(try await f.store.fusionReservedPrefix(recordingID: record.id) == "我想买苹")
    let reviewed = try await f.correction(ticket, "我想买梨子", evidence: pair)
    let result = try await f.store.publishFusion(ticket: ticket, proposal: reviewed)
    #expect(result.revision?.text == "我想买苹")
    // The first binding's already reserved range remains a no-op, even though the old
    // longer final is archived to prevent its newly disputed suffix from escaping.
    #expect(try await f.store.reserveDispatch(bindingID: first, recordingID: record.id, revisionID: old.id, stableUTF16End: 3) == nil)
}

@Test func fusionRevisionNewAcousticConflictCannotMakeOldAgreementFresh() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label: "isolated")
    let record = try await f.record(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let pair = try await f.pair(ticket, "我想买苹果")
    let agreement = PrecisionFusion.evaluate(candidates: pair, mode: .highestQuality)
    let initial = try #require(try await f.store.publishFusion(ticket: ticket, proposal: agreement).revision)
    _ = try await f.correction(ticket, "我想买梨子", evidence: pair)
    // Both old streaming IDs are still current; the new direct-audio source must also count.
    let stale = try await f.store.publishFusion(ticket: ticket, proposal: agreement)
    #expect(!stale.published)
    #expect(stale.deferred)
    #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id,
        revisionID: initial.id, stableUTF16End: initial.text.utf16.count) == nil)
    let current = try await f.store.latestRecognitionCandidates(ticket: ticket)
    _ = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: current, mode: .highestQuality))
    let head = try #require(try await f.store.latestDispatchableRevision(recordingID: record.id))
    #expect(head.text == "我想买")
}

@Test func fusionRevisionSelectedPrefixRetainsNewlyUnresolvedTailAtStoreBoundary() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let record = try await f.record(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let pair = try await f.pair(ticket, "去公园")
    let reviewed = try await f.correction(ticket, "去公园", evidence: pair)
    #expect(!reviewed.unresolved)
    for previous in pair {
        let updated = RecognitionCandidate(run: previous.run, sequence: 1, text: "去公园然后回家",
            stableUTF16Length: 7, audioEndSeconds: 2, isComplete: true)
        #expect(try await f.store.appendRecognitionCandidate(updated))
    }
    let result = try await f.store.publishFusion(ticket: ticket, proposal: reviewed)
    #expect(result.published)
    #expect(result.deferred)
    #expect(result.acceptedProposal?.unresolved == true)
    #expect(result.revision?.text == "去公园")
    #expect(try await f.store.fusionDecisions(recordingID: record.id).last?.proposal.unresolved == true)
}

@Test func fusionRevisionSameProposalAfterRetiredReviewRefreshesEvidenceWithoutNewText() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label: "isolated")
    let record = try await f.record(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    var live = try await f.pair(ticket, "去公园然后回家")
    live = try await live.asyncUpdatedForTail(store: f.store)
    let proposal = PrecisionFusion.evaluate(candidates: live, mode: .highestQuality)
    let old = try #require(try await f.store.publishFusion(ticket: ticket, proposal: proposal).revision)
    let run = try await f.store.beginModelRun(ticket: ticket, configuration: .init(purpose: .audioReview, provider: .gemini, model: "old-prefix"))
    #expect(try await f.store.appendRecognitionCandidate(.init(run: run, sequence: 0, text: "去公园", stableUTF16Length: 3, audioEndSeconds: 1, isComplete: true)))
    #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: old.id, stableUTF16End: old.text.utf16.count) == nil)
    // Retired review is deliberately outside active evidence, so this proposal is identical.
    #expect(try await !f.store.publishFusion(ticket: ticket, proposal: proposal).published)
    #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: old.id, stableUTF16End: old.text.utf16.count)?.text == old.text)
}

private extension Array where Element == RecognitionCandidate {
    func asyncUpdatedForTail(store: SaytileStore) async throws -> [RecognitionCandidate] {
        var updated: [RecognitionCandidate] = []
        for old in self {
            let value = RecognitionCandidate(run: old.run, sequence: old.sequence + 1, text: old.text,
                stableUTF16Length: old.text.utf16.count, audioEndSeconds: 3, isComplete: true)
            #expect(try await store.appendRecognitionCandidate(value)); updated.append(value)
        }
        return updated
    }
}

@Test func fusionRevisionMatchingLegacyHeadAdoptsFusionEvidenceFreshness() async throws {
    let f = try RevisionFixture(); defer { f.clean() }
    let binding = try await f.store.createBinding(label: "isolated")
    let record = try await f.record(), legacy = try await f.store.beginRecognition(recordingID: record.id)
    #expect(try await f.store.applyRecognition(ticket: legacy, text: "去公园", isFinal: true))
    try await f.store.finishRecognition(ticket: legacy)
    let old = try #require(try await f.store.latestDispatchableRevision(recordingID: record.id))
    let ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
    let pair = try await f.pair(ticket, old.text)
    #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: old.id, stableUTF16End: old.text.utf16.count) == nil)
    _ = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: pair, mode: .highestQuality))
    let changed = RecognitionCandidate(run: pair[0].run, sequence: 1, text: old.text,
        stableUTF16Length: old.text.utf16.count, audioEndSeconds: 1, isComplete: true)
    #expect(try await f.store.appendRecognitionCandidate(changed))
    #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: old.id, stableUTF16End: old.text.utf16.count) == nil)
    _ = try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: [changed, pair[1]], mode: .highestQuality))
    #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: old.id, stableUTF16End: old.text.utf16.count)?.text == old.text)
}
