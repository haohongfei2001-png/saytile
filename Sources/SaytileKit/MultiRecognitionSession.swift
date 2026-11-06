import Foundation

/// Dependency injection exercises the real coordinator without credentials or cloud traffic.
struct RecognitionPipelineDependencies: Sendable {
    var credential: @Sendable (ModelConfiguration) throws -> String?
    var streaming: @Sendable (CloudProvider) throws -> any StreamingASRProvider
    var transcribe: @Sendable (Data, ModelConfiguration, String) async throws -> ProviderTranscriptEvent
    var arbitrate: @Sendable ([ReviewEvidence], String, String, ModelConfiguration, String) async throws -> (PrecisionReviewDecision, PrecisionReviewUsage)
    var listen: @Sendable (Data, ModelConfiguration, String) async throws -> (AudioReviewTranscript, PrecisionReviewUsage)
    static let live = RecognitionPipelineDependencies(
        credential: { try CloudCredentialStore.read(configurationID: $0.id, provider: $0.provider) },
        streaming: { provider in
            switch provider {
            case .qwenMessage: return QwenMessageProvider()
            case .assemblyAI: return AssemblyStreamingProvider()
            case .soniox: return SonioxStreamingProvider()
            case .meta: return MetaStreamingProvider()
            case .elevenLabsRealtime: throw ProviderFailure.configuration("本轮未启用 ElevenLabs 实时适配；可使用 Scribe v2 文件复核。")
            default: throw ProviderFailure.configuration("所选服务不是实时识别接口。")
            }
        },
        transcribe: { try await FinalASRProvider().transcribe(pcm: $0, configuration: $1, credential: $2) },
        arbitrate: { try await PrecisionReviewClient().arbitrate(evidence: $0, confirmedPrefix: $1, context: $2, configuration: $3, credential: $4) },
        listen: { try await PrecisionReviewClient().listen(pcm: $0, configuration: $1, credential: $2) })
}

final class MultiRecognitionSession: RecognitionSession, @unchecked Sendable {
    let recordingID: UUID
    private let completion = RecognitionSessionCompletion()
    private let fanout: RecognitionAudioFanout
    private let coordinator: SingleTranscriptEngine
    private let task: Task<Void, Never>
    var isComplete: Bool { completion.isComplete }
    init(store: SaytileStore, ticket: RecognitionTicket, configuration: RecognitionConfiguration,
         dependencies: RecognitionPipelineDependencies = .live,
         allowSingleExpertBaseline: Bool = false,
         onComplete: @escaping @Sendable () -> Void = {}) {
        self.recordingID = ticket.recordingID
        let configs = configuration.enabledModels.filter { $0.purpose.isStreaming }
        let coordinator = SingleTranscriptEngine(store: store, ticket: ticket, configuration: configuration, dependencies: dependencies)
        self.coordinator = coordinator
        let fanout = RecognitionAudioFanout(ids: configs.map(\.id)) { id in
            Task { await coordinator.audioOverflow(configurationID: id) }
        }
        self.fanout = fanout
        let completion = completion
        task = Task {
            defer { completion.finish(); onComplete() }
            do {
                try configuration.validateForCloud(allowSingleExpertBaseline: allowSingleExpertBaseline)
                try await coordinator.attach(fanout)
                try Task.checkCancellation()
                await withTaskCancellationHandler {
                    await withTaskGroup(of: Void.self) { group in
                        for (index, item) in configs.enumerated() {
                            let stream = fanout.channels[index].audio
                            group.addTask { await coordinator.runStreaming(item, audio: stream) }
                        }
                        await group.waitForAll()
                    }
                } onCancel: {
                    fanout.finish()
                    Task { await coordinator.cancel() }
                }
                try Task.checkCancellation()
                await coordinator.finalize()
            } catch {
                await coordinator.cancel()
                try? await store.failRecognition(ticket: ticket, message: error is CancellationError ? "识别已暂停，原音和候选已保留。" : Self.safeMessage(error))
            }
        }
    }
    func append(_ data: Data) { fanout.append(data) }
    func finish() {
        fanout.finish()
        let task = task
        completion.watch(Task {
            // A liveness deadline never turns incomplete evidence into stable text.
            do { try await Task.sleep(for: .seconds(480)) } catch { return }
            task.cancel()
        })
    }
    func cancel() { fanout.finish(); task.cancel(); Task { await coordinator.cancel() } }
    func wait() async { await task.value }
    static func safeMessage(_ error: Error) -> String {
        if let error = error as? ProviderFailure { return error.localizedDescription }
        if let error = error as? FusionError { return error.localizedDescription }
        return "模型连接或处理失败；原音和候选已保留。"
    }
}

