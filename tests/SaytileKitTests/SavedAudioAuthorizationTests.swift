import Foundation
import Testing
@testable import SaytileKit

private actor SavedAuthorizationProbe {
    var cloudBytes: [CloudProvider: Data] = [:]
    var localBytes = Data()
    var localStarts = 0
    func cloud(_ data: Data, provider: CloudProvider) { cloudBytes[provider, default: Data()].append(data) }
    func local(_ data: Data) { localBytes.append(data) }
    func startLocal() { localStarts += 1 }
}
private struct AuthorizedCloudProvider: StreamingASRProvider {
    let probe: SavedAuthorizationProbe
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        var count = 0
        for await data in audio { try Task.checkCancellation(); count += data.count; await probe.cloud(data, provider: configuration.provider) }
        try Task.checkCancellation()
        try await emit(.init(text: "不要发送", stableUTF16Length: 4, audioEndSeconds: Double(count) / 32_000,
                             timingGranularity: "utterance", isComplete: true))
    }
}
private final class AuthorizedLocalSession: RecognitionSession, @unchecked Sendable {
    let recordingID: UUID
    let input: AsyncStream<Data>.Continuation
    let completion = RecognitionSessionCompletion()
    let task: Task<Void, Never>
    var isComplete: Bool { completion.isComplete }
    init(store: SaytileStore, ticket: RecognitionTicket, probe: SavedAuthorizationProbe) {
        recordingID = ticket.recordingID
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        input = continuation
        let completion = completion
        task = Task {
            defer { completion.finish() }
            await probe.startLocal()
            let ingress = LocalCandidateIngress(store: store, ticket: ticket)
            do {
                var count = 0
                for await data in stream { try Task.checkCancellation(); count += data.count; await probe.local(data) }
                try Task.checkCancellation()
                try await ingress.receive(.init(text: "不要发送", stableUTF16Length: 4,
                    audioEndSeconds: Double(count) / 32_000, timingGranularity: "utterance", isComplete: true))
                try await ingress.finish()
            } catch { try? await store.failRecognition(ticket: ticket, message: "isolated local cancellation") }
        }
    }
    func append(_ data: Data) { input.yield(data) }
    func finish() { input.finish() }
    func cancel() { input.finish(); task.cancel() }
    func wait() async { await task.value }
}
private func savedAuthorizationConfig() -> RecognitionConfiguration {
    var config = RecognitionConfiguration(); config.languagePreference = .chinese; config.cloudEnabled = true
    for index in config.models.indices {
        config.models[index].cloudConsent = true
        if config.models[index].provider == .qwenMessage { config.models[index].workspaceID = "isolated-recovery" }
    }
    return config
}
private func authorizationFactory(_ config: RecognitionConfiguration, probe: SavedAuthorizationProbe, localInstalled: Bool = true) -> RecognitionSessionFactory {
    let dependencies = RecognitionPipelineDependencies(credential: { _ in "synthetic-not-a-key" },
        streaming: { _ in AuthorizedCloudProvider(probe: probe) },
        transcribe: { _, _, _ in throw ProviderFailure.incomplete },
        arbitrate: { evidence, _, _, _, _ in
            guard let source = evidence.first else { throw ProviderFailure.incomplete }
            return (.init(selections: [.init(candidateID: source.candidateID, utf16Start: 0, utf16End: source.text.utf16.count)],
                          unresolved: false, needsAudioReview: false, reasonCode: "synthetic-recovery"),
                    .init(requestID: nil, inputTokens: nil, outputTokens: nil, elapsedSeconds: 0))
        }, listen: { _, _, _ in throw ProviderFailure.incomplete })
    return RecognitionSessionFactory(configuration: config, dependencies: dependencies,
        local: .init(availability: { .init(supported: true, installed: localInstalled, message: "isolated local") },
                     make: { AuthorizedLocalSession(store: $0, ticket: $1, probe: probe) }))
}

@Suite("Saved audio cannot inherit later cloud or account permission")
struct SavedAudioAuthorizationTests {
    @MainActor @Test(arguments: ["legacy-local", "apple-candidate", "authorized-cloud", "changed-workspace", "changed-fusion", "changed-key"])
    func automaticRetryUsesPersistedScopeAcrossRestart(origin: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-saved-auth-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try SaytileStore(directory: root)
        let record = try await original.createRecording()
        let pcm = Data((0..<640).map { UInt8($0 % 251) })
        let journal = try PCMJournal(directory: original.audioDirectory, recordingID: record.id)
        try journal.openChunk(); try journal.append(pcm); try journal.closeChunk()
        try await original.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: journal.frames)
        try await original.finishRecording(id: record.id)
        var config = savedAuthorizationConfig()
        if origin == "apple-candidate" {
            let ticket = try await original.beginRecognition(recordingID: record.id)
            let ingress = LocalCandidateIngress(store: original, ticket: ticket)
            try await ingress.receive(.init(text: "本机旧稿", stableUTF16Length: 4, audioEndSeconds: 0.02, timingGranularity: "utterance", isComplete: true))
            try await ingress.finish()
        }
        if !["legacy-local", "apple-candidate"].contains(origin) {
            try await original.authorizeCloudRecovery(recordingID: record.id, configuration: config)
        }
        if origin == "changed-workspace" { config.models[0].workspaceID = "different-account" }
        if origin == "changed-key" { config.models[0].credentialGeneration = UUID() }
        if origin == "changed-fusion" {
            let index = try #require(config.models.firstIndex { $0.purpose == .textFusion })
            config.models[index].id = UUID()
        }
        try await original.queueRecognition(recordingID: record.id)
        try await original.close()
        let store = try SaytileStore(directory: root), probe = SavedAuthorizationProbe()
        let controller = AudioController(store: store, recognitionFactory: authorizationFactory(config, probe: probe), startupRecoveryReady: false)
        let claimed = try #require(await store.claimRecoveryRecording())
        #expect(claimed.id == record.id)
        await controller.retry(recordingID: record.id, isAutomatic: true)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while try await store.recording(id: record.id)?.recognitionState != .completed {
            guard ContinuousClock.now < deadline else { await controller.shutdown(); throw ProviderFailure.incomplete }
            try await Task.sleep(for: .milliseconds(5))
        }
        await controller.shutdown()
        if origin == "authorized-cloud" {
            #expect(await probe.cloudBytes[.qwenMessage] == pcm)
            #expect(await probe.cloudBytes[.assemblyAI] == nil)
            #expect(await probe.localStarts == 0)
        } else {
            #expect(await probe.cloudBytes.isEmpty)
            #expect(await probe.localBytes == pcm)
            #expect(await probe.localStarts == 1)
            #expect(try await !store.permitsAutomaticCloudRecovery(recordingID: record.id, configuration: config))
        }
        #expect(try Data(contentsOf: await store.audioURL(for: #require(await store.audioChunks(recordingID: record.id).first))).dropFirst(44) == pcm)
        try await store.close()
    }

    @MainActor @Test(arguments: ["match", "local-ui", "new-account"])
    func explicitRetryRespectsTheConfigurationShownAtClick(shown: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-explicit-auth-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root), config = savedAuthorizationConfig(), probe = SavedAuthorizationProbe()
        let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 32_000), sampleRate: 16_000, recognitionEnabled: false,
                                       update: { _, _ in }, failed: { _ in })
        var ids: [UUID] = []
        let pcm = Data(repeating: 3, count: 640)
        for _ in 0..<2 {
            try await worker.beginUtterance(); ids.append(try #require(await worker.recordingID))
            try await worker.append(pcm); try await worker.endUtterance()
        }
        let controller = AudioController(store: store, recognitionFactory: authorizationFactory(config, probe: probe), startupRecoveryReady: false)
        var shownConfiguration = config
        if shown == "local-ui" { shownConfiguration.cloudEnabled = false }
        if shown == "new-account" { shownConfiguration.models[0].credentialGeneration = UUID() }
        await controller.retry(recordingID: ids[0], expectedConfiguration: shownConfiguration)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while try await store.recording(id: ids[0])?.recognitionState != .completed {
            guard ContinuousClock.now < deadline else { await controller.shutdown(); throw ProviderFailure.incomplete }
            try await Task.sleep(for: .milliseconds(5))
        }
        await controller.shutdown()
        #expect(try await store.permitsAutomaticCloudRecovery(recordingID: ids[0], configuration: config) == (shown == "match"))
        #expect(try await !store.permitsAutomaticCloudRecovery(recordingID: ids[1], configuration: config))
        if shown == "match" {
            #expect(await probe.cloudBytes[.qwenMessage] == pcm)
            #expect(await probe.cloudBytes[.assemblyAI] == nil)
        } else {
            #expect(await probe.cloudBytes.isEmpty)
            #expect(await probe.localBytes == pcm)
        }
        try await store.close()
    }
    @MainActor @Test func unavailableLocalResourcesDoNotExhaustLegacyAudioRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-wait-local-auth-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root), config = savedAuthorizationConfig(), probe = SavedAuthorizationProbe()
        let record = try await store.createRecording()
        try await store.finishRecording(id: record.id)
        let controller = AudioController(store: store,
            recognitionFactory: authorizationFactory(config, probe: probe, localInstalled: false), startupRecoveryReady: false)
        let inspect = try StoreDatabase(url: root.appendingPathComponent("Saytile.sqlite"))
        for attempt in 1...4 {
            let candidate = try #require(await store.claimRecoveryRecording(now: Date().addingTimeInterval(Double(attempt * 3600))))
            #expect(candidate.id == record.id)
            await controller.retry(recordingID: record.id, isAutomatic: true)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while try inspect.rows("SELECT attempt_count FROM recovery_attempts").first?["attempt_count"] != "0" {
                guard ContinuousClock.now < deadline else { await controller.shutdown(); throw ProviderFailure.incomplete }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        await controller.shutdown()
        #expect(await probe.cloudBytes.isEmpty)
        #expect(await probe.localStarts == 0)
        #expect(try await store.recording(id: record.id)?.recognitionState == .queued)
        try inspect.close(); try await store.close()
    }

}
