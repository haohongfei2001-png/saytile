import Foundation
import Testing
@testable import SaytileKit

private actor CaptureCloudProbe {
    var streaming: [CloudProvider: Data] = [:]
    var acoustic: [RecognitionPurpose: Data] = [:]
    var reviews: [[ReviewEvidence]] = []
    func append(_ data: Data, provider: CloudProvider) { streaming[provider, default: Data()].append(data) }
    func hear(_ data: Data, purpose: RecognitionPurpose) { acoustic[purpose] = data }
    func arbitrate(_ evidence: [ReviewEvidence]) throws -> PrecisionReviewDecision {
        reviews.append(evidence)
        let source = try #require(evidence.first { $0.role == RecognitionPurpose.audioReview.rawValue }
            ?? evidence.first { $0.role == RecognitionPurpose.chineseASR.rawValue })
        return .init(selections: [.init(candidateID: source.candidateID, utf16Start: 0, utf16End: source.text.utf16.count)],
                     unresolved: false, needsAudioReview: false, reasonCode: "synthetic-capture-evidence")
    }
}
private struct CaptureCloudProvider: StreamingASRProvider {
    let probe: CaptureCloudProbe
    let text: String
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        var bytes = 0
        for await data in audio {
            await probe.append(data, provider: configuration.provider); bytes += data.count
            // Genuine production preview path, without inventing stable utterance alignment.
            try await emit(.init(text: text, stableUTF16Length: 0, audioEndSeconds: Double(bytes) / 32_000, isComplete: false))
        }
        try await emit(.init(text: text, stableUTF16Length: text.utf16.count,
                             audioEndSeconds: Double(bytes) / 32_000, timingGranularity: "utterance", isComplete: true))
    }
}

@Suite("Production capture to five-role recognition with isolated transports")
struct CaptureCloudIntegrationTests {
    @Test(arguments: [false, true]) func journalAndFiveRolePipelineShareAudioAndPreserveReviewFailure(failReview: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-capture-cloud-" + UUID().uuidString)
        let store = try SaytileStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binding = try await store.createBinding(label: "isolated capture ledger")
        let probe = CaptureCloudProbe()
        let good = "请不要删除 API 项目。", other = "请不要移除 API 项目。"
        var config = RecognitionConfiguration(); config.cloudEnabled = true; config.inputMode = .highestQuality
        config.models = [
            .init(purpose: .chineseASR, provider: .qwenMessage, model: "qwen-audio-3.1-asr-flash-message", cloudConsent: true, region: "cn-beijing", workspaceID: "isolated"),
            .init(purpose: .englishASR, provider: .assemblyAI, model: "universal-3-6-pro", cloudConsent: true),
            .init(purpose: .textFusion, provider: .openAIResponses, model: "gpt-6-astra", cloudConsent: true),
            .init(purpose: .audioReview, provider: .gemini, model: "gemini-3.8-flash", cloudConsent: true),
            .init(purpose: .finalASR, provider: .elevenLabsFile, model: "scribe_v2", cloudConsent: true)
        ]
        let deps = RecognitionPipelineDependencies(credential: { _ in "synthetic-nonsecret-sentinel" },
            streaming: { CaptureCloudProvider(probe: probe, text: $0 == .qwenMessage ? good : other) },
            transcribe: { pcm, _, _ in
                await probe.hear(pcm, purpose: .finalASR)
                return .init(text: good, stableUTF16Length: good.utf16.count, audioEndSeconds: Double(pcm.count) / 32_000,
                             timingGranularity: "utterance", isComplete: true)
            },
            arbitrate: { evidence, _, _, _, _ in
                (try await probe.arbitrate(evidence), .init(requestID: "offline", inputTokens: nil, outputTokens: nil, elapsedSeconds: 0))
            },
            listen: { pcm, _, _ in
                await probe.hear(pcm, purpose: .audioReview)
                if failReview { throw ProviderFailure.connection }
                return (.init(text: good, uncertain: false), .init(requestID: "offline", inputTokens: nil, outputTokens: nil, elapsedSeconds: 0))
            })
        let factory = RecognitionSessionFactory(configuration: config, dependencies: deps)
        let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 32_000), sampleRate: 16_000,
                                       recognitionFactory: factory, update: { _, _ in }, failed: { _ in })
        try await worker.beginUtterance()
        let id = try #require(await worker.recordingID)
        let pcm = Data((0..<6_400).map { UInt8($0 % 251) })
        try await worker.append(pcm)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try await store.recording(id: id)?.text.isEmpty != false {
            guard ContinuousClock.now < deadline else { Issue.record("Production preview did not reach the recording"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try await store.recording(id: id)?.isRecording == true)
        try await worker.endUtterance()
        for session in await worker.retired { await session.wait() }
        #expect(await probe.streaming[.qwenMessage] == pcm)
        #expect(await probe.streaming[.assemblyAI] == pcm)
        #expect(await probe.acoustic[.audioReview] == pcm)
        #expect(await probe.acoustic[.finalASR] == pcm)
        #expect(!(await probe.reviews).isEmpty)
        let chunks = try await store.audioChunks(recordingID: id)
        var stored = Data()
        for chunk in chunks { stored.append(try Data(contentsOf: await store.audioURL(for: chunk)).dropFirst(44)) }
        #expect(stored == pcm)
        let record = try #require(await store.recording(id: id))
        #expect(!record.text.isEmpty && !record.isRecording)
        #expect(record.recognitionState == (failReview ? .failed : .completed))
        let runs = try await store.modelRuns(recordingID: id)
        #expect(Set(runs.map { $0.ticket.purpose }) == Set(config.models.map(\.purpose)))
        let revisions = try await store.revisions(recordingID: id)
        #expect(!revisions.isEmpty)
        if !failReview {
            let revision = try #require(await store.latestDispatchableRevision(recordingID: id))
            #expect(revision.text == good)
            let dispatch = try await store.reserveDispatch(bindingID: binding, recordingID: id, revisionID: revision.id,
                                                          stableUTF16End: revision.text.utf16.count)
            #expect(dispatch?.text == good)
            #expect(try await store.reserveDispatch(bindingID: binding, recordingID: id, revisionID: revision.id,
                                                    stableUTF16End: revision.text.utf16.count) == nil)
        }
    }
}
