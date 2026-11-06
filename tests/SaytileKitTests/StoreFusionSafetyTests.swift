import Foundation
import Testing
@testable import SaytileKit

private struct StoreFusionFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-store-fusion-" + UUID().uuidString)
    let store: SaytileStore
    init() throws { store = try SaytileStore(directory: directory) }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    func candidate(_ ticket: RecognitionTicket, config: ModelConfiguration, text: String = "去公园") async throws -> RecognitionCandidate {
        let run = try await store.beginModelRun(ticket: ticket, configuration: config)
        let value = RecognitionCandidate(run: run, sequence: 0, text: text,
            stableUTF16Length: text.utf16.count, audioEndSeconds: 1, isComplete: true)
        #expect(try await store.appendRecognitionCandidate(value))
        return value
    }
}

@Suite("Fusion store authority and measurement")
struct StoreFusionSafetyTests {
    @Test func configuredSamePurposeExpertCannotBeSilentlyOmittedByAgreementOrSelection() async throws {
        let f = try StoreFusionFixture(); defer { f.clean() }
        let record = try await f.store.createRecording(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
        let zh = ModelConfiguration(purpose: .chineseASR, provider: .qwenMessage, model: "fixture")
        let en = ModelConfiguration(purpose: .englishASR, provider: .assemblyAI, model: "fixture")
        let extra = ModelConfiguration(purpose: .englishASR, provider: .meta, model: "fixture-extra")
        try await f.store.configureFusionRequirements(ticket: ticket, configurations: [zh, en, extra])
        let first = try await f.candidate(ticket, config: zh), second = try await f.candidate(ticket, config: en)
        await #expect(throws: FusionError.self) {
            try await f.store.publishFusion(ticket: ticket, proposal: PrecisionFusion.evaluate(candidates: [first, second], mode: .highestQuality))
        }
        let selection = try PrecisionFusion.validateSelection(spans: [.init(candidateID: first.id, utf16Start: 0, utf16End: first.text.utf16.count)], candidates: [first, second])
        await #expect(throws: FusionError.self) { try await f.store.publishFusion(ticket: ticket, proposal: selection) }
        #expect(try await f.store.latestDispatchableRevision(recordingID: record.id) == nil)
        let third = try await f.candidate(ticket, config: extra)
        let ready = PrecisionFusion.evaluate(candidates: [first, second, third], mode: .highestQuality,
            requiredConfigurationIDs: [zh.id, en.id, extra.id])
        #expect(try await f.store.publishFusion(ticket: ticket, proposal: ready).published)
    }

    @Test func explicitSingleExpertDiagnosticUsesItsActualIdentityWithoutFakeSecondRole() async throws {
        let f = try StoreFusionFixture(); defer { f.clean() }
        let record = try await f.store.createRecording(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
        let en = ModelConfiguration(purpose: .englishASR, provider: .assemblyAI, model: "single-baseline")
        try await f.store.configureFusionRequirements(ticket: ticket, configurations: [en])
        let candidate = try await f.candidate(ticket, config: en, text: "Build this with SwiftUI.")
        let proposal = PrecisionFusion.evaluate(candidates: [candidate], mode: .highestQuality,
            requiredPurposes: [.englishASR], requiredConfigurationIDs: [en.id])
        #expect(try await f.store.publishFusion(ticket: ticket, proposal: proposal).published)
        #expect(try await f.store.modelRuns(recordingID: record.id).count == 1)
    }

    @Test func requirementsAreFrozenBeforeProviderAttemptsAndCannotBeDowngraded() async throws {
        let f = try StoreFusionFixture(); defer { f.clean() }
        let record = try await f.store.createRecording(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
        let en = ModelConfiguration(purpose: .englishASR, provider: .assemblyAI, model: "fixture")
        await #expect(throws: FusionError.self) { try await f.store.configureFusionRequirements(ticket: ticket, configurations: []) }
        await #expect(throws: FusionError.self) { try await f.store.configureFusionRequirements(ticket: ticket, configurations: [en, en]) }
        try await f.store.configureFusionRequirements(ticket: ticket, configurations: [en])
        await #expect(throws: FusionError.self) { try await f.store.configureFusionRequirements(ticket: ticket, configurations: [en]) }
        _ = try await f.candidate(ticket, config: en)
        await #expect(throws: FusionError.self) { try await f.store.configureFusionRequirements(ticket: ticket, configurations: [en]) }
        let another = try await f.store.createRecording(), unconfigured = try await f.store.beginFusionRecognition(recordingID: another.id)
        _ = try await f.candidate(unconfigured, config: en)
        await #expect(throws: FusionError.self) { try await f.store.configureFusionRequirements(ticket: unconfigured, configurations: [en]) }
    }

    @Test func actualTerminalTimeIsGenerationSpecificDurableAndNeverBackfilledFromRestart() async throws {
        let f = try StoreFusionFixture(); defer { f.clean() }
        let record = try await f.store.createRecording(), first = try await f.store.beginFusionRecognition(recordingID: record.id)
        #expect(try await f.store.fusionTerminal(recognitionID: first.id) == nil)
        let before = Date()
        try await f.store.finishRecognition(ticket: first)
        let after = Date(), completed = try #require(try await f.store.fusionTerminal(recognitionID: first.id))
        #expect(completed.state == "completed")
        #expect(completed.occurredAt >= before && completed.occurredAt <= after)
        let second = try await f.store.beginFusionRecognition(recordingID: record.id)
        try await f.store.failRecognition(ticket: second, message: "authored failure")
        #expect(try await f.store.fusionSessionState(recognitionID: first.id) == "completed")
        #expect(try await f.store.fusionSessionState(recognitionID: second.id) == "failed")
        try await f.store.finishRecognition(ticket: first) // Stale callback cannot overwrite terminal time.
        #expect(try await f.store.fusionTerminal(recognitionID: first.id)?.occurredAt == completed.occurredAt)
        let third = try await f.store.beginFusionRecognition(recordingID: record.id)
        try await f.store.close()
        let reopened = try SaytileStore(directory: f.directory)
        #expect(try await reopened.fusionSessionState(recognitionID: third.id) == "interrupted")
        #expect(try await reopened.fusionTerminal(recognitionID: third.id) == nil)
        #expect(try await reopened.fusionTerminal(recognitionID: first.id)?.occurredAt == completed.occurredAt)
        try await reopened.close()
    }

    @Test func submittedAudioProgressIsMeasuredMetadataAndRejectsNonfiniteValues() async throws {
        let f = try StoreFusionFixture(); defer { f.clean() }
        let record = try await f.store.createRecording(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
        let zh = try await f.candidate(ticket, config: .init(purpose: .chineseASR, provider: .qwenMessage, model: "fixture"))
        let en = try await f.candidate(ticket, config: .init(purpose: .englishASR, provider: .assemblyAI, model: "fixture"))
        let proposal = PrecisionFusion.evaluate(candidates: [zh, en], mode: .highestQuality)
        for bad in [Double.nan, Double.infinity, -1] {
            await #expect(throws: FusionError.self) { try await f.store.publishFusion(ticket: ticket, proposal: proposal, audioSubmittedSeconds: bad) }
        }
        _ = try await f.store.publishFusion(ticket: ticket, proposal: proposal, audioSubmittedSeconds: 1.25)
        #expect(try await f.store.fusionDecisions(recordingID: record.id).last?.audioSubmittedSeconds == 1.25)
    }

    @Test func failedRequiredRunCannotKeepItsOldAgreementDispatchableOrBlockSafeRetraction() async throws {
        let f = try StoreFusionFixture(); defer { f.clean() }
        let binding = try await f.store.createBinding(label: "isolated")
        let record = try await f.store.createRecording(), ticket = try await f.store.beginFusionRecognition(recordingID: record.id)
        let zhConfig = ModelConfiguration(purpose: .chineseASR, provider: .qwenMessage, model: "fixture")
        let enConfig = ModelConfiguration(purpose: .englishASR, provider: .assemblyAI, model: "fixture")
        try await f.store.configureFusionRequirements(ticket: ticket, configurations: [zhConfig, enConfig])
        let zh = try await f.candidate(ticket, config: zhConfig), en = try await f.candidate(ticket, config: enConfig)
        let agreement = PrecisionFusion.evaluate(candidates: [zh, en], mode: .highestQuality,
            requiredConfigurationIDs: [zhConfig.id, enConfig.id])
        let head = try #require(try await f.store.publishFusion(ticket: ticket, proposal: agreement).revision)
        try await f.store.finishModelRun(zh.run, error: "authored connection failure", retryable: true)
        // The failure changes no candidate IDs, so identity-only freshness is insufficient.
        #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: record.id,
            revisionID: head.id, stableUTF16End: head.text.utf16.count) == nil)
        let stale = try await f.store.publishFusion(ticket: ticket, proposal: agreement)
        #expect(!stale.published && stale.deferred && stale.acceptedProposal == nil)
        let held = FusionProposal(previewText: agreement.previewText, stableText: "",
            sourceCandidateIDs: agreement.sourceCandidateIDs, unresolved: true,
            needsAudioReview: false, reasonCode: "expert-failed-evidence-retained")
        let withdrawn = try await f.store.publishFusion(ticket: ticket, proposal: held)
        #expect(withdrawn.acceptedProposal?.stableText == "")
        #expect(withdrawn.acceptedProposal?.unresolved == true)
        #expect(try await f.store.latestDispatchableRevision(recordingID: record.id) == nil)
        #expect(try await f.store.revisions(recordingID: record.id).contains { $0.id == head.id })
    }
}
