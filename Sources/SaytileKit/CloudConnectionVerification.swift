import Foundation
import CryptoKit

/// These are evidence levels, never a model quality score.
public enum ProductReadiness: String, Codable, Sendable {
    case noAPIEngineeringReady = "NO_API_ENGINEERING_READY"
    case liveConnectionPending = "LIVE_CONNECTION_PENDING"
    case liveProtocolVerified = "LIVE_PROTOCOL_VERIFIED"
    case liveTranscriptionVerified = "LIVE_TRANSCRIPTION_VERIFIED"
    case qualityVerified = "QUALITY_VERIFIED"
    case productionReady = "PRODUCTION_READY"
}
public enum ConnectionServiceState: String, Codable, Sendable {
    case waiting, connecting, accountAccepted, receiving, verified, failed, cancelled
    public var label: String {
        switch self {
        case .waiting: "等待检查"
        case .connecting: "正在连接"
        case .accountAccepted: "账户已接受，等待文字"
        case .receiving: "正在接收文字"
        case .verified: "检查通过"
        case .failed: "需要处理"
        case .cancelled: "已停止"
        }
    }
}
public struct ConnectionServiceResult: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let provider: CloudProvider
    public var state: ConnectionServiceState
    public var code: String?
    public var message: String?
}
public struct CloudConnectionReport: Codable, Sendable, Equatable {
    public let configurationFingerprint: String
    public let date: Date
    public let live: Bool
    public var services: [ConnectionServiceResult]
    public var transcript = ""
    public var pipelineCompleted = false
    public var elapsedSeconds: Double = 0
    public var reviewRequests = 0
    public var message: String?
    public var usage: [ModelUsageRecord]? = nil
    public var runs: [ModelRunRecord]? = nil
    public var readiness: ProductReadiness {
        guard live else { return .noAPIEngineeringReady }
        guard services.count == 2, Set(services.map(\.id)).count == 2,
              services.filter({ $0.provider.isStreaming }).count == 1,
              services.contains(where: { $0.provider == .openAIResponses }) else { return .liveConnectionPending }
        if pipelineCompleted && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && services.allSatisfy({ $0.state == .verified }) { return .liveTranscriptionVerified }
        if services.allSatisfy({ $0.state == .verified }) { return .liveProtocolVerified }
        return .liveConnectionPending
    }
    public var canEnableCloud: Bool { readiness == .liveTranscriptionVerified }
    public func matches(_ configuration: RecognitionConfiguration) -> Bool {
        configurationFingerprint == CloudConnectionVerifier.fingerprint(configuration)
    }
}

/// One explicitly authorized attempt. Retries and HTTP fallback share this budget.
public enum ConnectionCheckLimits {
    public static let maximumAudioSeconds = 12.0
    public static let maximumDuration: Duration = .seconds(90)
    public static let maximumReviewRequests = 6
    public static let maximumOutputTokens = 4096
    public static let disclosure = "只上传应用内置的 6.3 秒合成语音，不使用麦克风或你的历史内容。每次仅连接一项语言 ASR、最多 6 次 GPT-6 请求，每次最多 4096 输出 Token，联网阶段 90 秒内停止；可随时取消。按标准公开价格，仅 AI 输出的上限估算约 US$1.23，另有输入、缓存及语音费用；实际以账户账单为准，不能保证金额上限。不会自动重试本次检查。"
}

struct CloudConnectionTransport: Sendable {
    var live = true
    var credential: @Sendable (ModelConfiguration) throws -> String? = {
        try CloudCredentialStore.read(configurationID: $0.id, provider: $0.provider)
    }
    var streaming: @Sendable (CloudProvider, @escaping @Sendable () -> Void) throws -> any StreamingASRProvider = { provider, ready in
        switch provider {
        case .qwenMessage: QwenMessageProvider(onReady: ready)
        case .assemblyAI: AssemblyStreamingProvider(onReady: ready)
        default: throw ProviderFailure.configuration("连接检查仅启用中文、英文专家与一个融合核心。")
        }
    }
    var socket: GPTReviewSession.Factory = { NativeGPTReviewSocket(credential: $0) }
    var fallback: GPTReviewSession.Fallback = {
        try await PrecisionReviewClient(maximumOutputTokens: ConnectionCheckLimits.maximumOutputTokens)
            .arbitrate(evidence: $0, confirmedPrefix: $1, context: $2, configuration: $3, credential: $4)
    }
}

final class ConnectionRequestBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    var count: Int { lock.withLock { requests } }
    func reserve() throws {
        try lock.withLock {
            guard requests < ConnectionCheckLimits.maximumReviewRequests else {
                throw ProviderFailure.configuration("连接检查已达到 6 次 AI 请求上限，请查看服务状态后再试。")
            }
            requests += 1
        }
    }
}
private struct BudgetedReviewSocket: GPTReviewSocket {
    let underlying: any GPTReviewSocket
    let budget: ConnectionRequestBudget
    func send(_ data: Data) async throws { try budget.reserve(); try await underlying.send(data) }
    func receive() async throws -> Data { try await underlying.receive() }
    func close() { underlying.close() }
}

private final class ConnectionProgress: @unchecked Sendable {
    let lock = NSLock()
    private var value: CloudConnectionReport
    let update: @Sendable (CloudConnectionReport) -> Void
    init(configuration: RecognitionConfiguration, live: Bool, update: @escaping @Sendable (CloudConnectionReport) -> Void) {
        value = .init(configurationFingerprint: CloudConnectionVerifier.fingerprint(configuration), date: Date(), live: live,
                      services: configuration.activeModels.map { .init(id: $0.id, provider: $0.provider, state: .waiting) })
        self.update = update
    }
    var snapshot: CloudConnectionReport { lock.withLock { value } }
    func set(_ id: UUID, _ state: ConnectionServiceState, error: Error? = nil) {
        let report = lock.withLock {
            if let index = value.services.firstIndex(where: { $0.id == id }) {
                // A delayed handshake/partial must not erase a terminal outcome.
                if [.failed, .cancelled, .verified].contains(value.services[index].state), error == nil { return value }
                value.services[index].state = state
                if let error {
                    let failure = (error as? ProviderFailure) ?? (error is CancellationError ? .cancelled : .connection)
                    value.services[index].code = failure.diagnosticCode
                    value.services[index].message = failure.localizedDescription
                }
            }
            return value
        }
        update(report)
    }
}
private struct ObservedConnectionProvider: StreamingASRProvider {
    let underlying: any StreamingASRProvider
    let progress: ConnectionProgress
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        do {
            progress.set(configuration.id, .connecting)
            try await underlying.run(audio: audio, configuration: configuration, credential: credential) { event in
                try await emit(event)
                if !event.text.isEmpty { progress.set(configuration.id, .receiving) }
            }
        } catch { progress.set(configuration.id, .failed, error: error); throw error }
    }
}

public enum CloudConnectionVerifier {
    /// Endpoint/account identity only: topic, prices and the on/off switch do not re-authenticate an account.
    public static func fingerprint(_ configuration: RecognitionConfiguration) -> String {
        let rows = configuration.activeModels.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            [$0.id.uuidString, $0.provider.rawValue, $0.purpose.rawValue, $0.model, $0.region, $0.workspaceID,
             String($0.enabled), String($0.cloudConsent), $0.credentialGeneration?.uuidString ?? "legacy-credential"]
        }
        let canonical = [configuration.languagePreference?.rawValue ?? "auto", configuration.resolvedLanguage.rawValue,
                         rows.map { $0.joined(separator: "|") }.joined(separator: "\n")].joined(separator: "\n")
        let bytes = Data(canonical.utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    public static func bundledSample() throws -> Data {
        // Direct bundle resource also supports manually linked native fixture tools.
        var url = Bundle.main.url(forResource: "ConnectionSample", withExtension: "pcm")
        #if SWIFT_PACKAGE
        if url == nil { url = Bundle.module.url(forResource: "ConnectionSample", withExtension: "pcm") }
        #endif
        guard let url else { throw ProviderFailure.configuration("连接检查语音缺失，请重新安装 Saytile。") }
        let data = try Data(contentsOf: url)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == "5d29f5fc799a571b27d80bcf442004ba78a619c0d6e847258bb2b6b8b075387a" else {
            throw ProviderFailure.configuration("连接检查语音校验失败，请重新安装 Saytile。")
        }
        return data
    }
    public static func verify(configuration: RecognitionConfiguration, authorized: Bool,
                              progress: @escaping @Sendable (CloudConnectionReport) -> Void) async throws -> CloudConnectionReport {
        try await run(configuration: configuration, authorized: authorized, pcm: bundledSample(), transport: .init(), progress: progress)
    }
    static func run(configuration: RecognitionConfiguration, authorized: Bool, pcm: Data,
                    transport: CloudConnectionTransport, deadline: Duration = ConnectionCheckLimits.maximumDuration,
                    paced: Bool = true, progress update: @escaping @Sendable (CloudConnectionReport) -> Void) async throws -> CloudConnectionReport {
        try Task.checkCancellation()
        guard authorized else { throw ProviderFailure.authorization }
        var check = configuration; check.cloudEnabled = true
        check.languagePreference = configuration.resolvedLanguage; check.automaticRecovery = false
        try check.validateForCloud()
        guard check.activeModels.count == 2,
              check.activeModels.filter({ $0.purpose.isStreaming }).count == 1,
              check.activeModels.contains(where: { $0.purpose == .textFusion && $0.provider == .openAIResponses }),
              !pcm.isEmpty, pcm.count.isMultiple(of: 2), Double(pcm.count) / 32000 <= ConnectionCheckLimits.maximumAudioSeconds else {
            throw ProviderFailure.configuration("请准备当前语言对应的一项 ASR 服务和 GPT-6 AI 核心。")
        }
        // Never upload a user's topic, archive or microphone audio during setup.
        check.topicContext = ""
        for index in check.models.indices { check.models[index].context = "" }
        let progress = ConnectionProgress(configuration: configuration, live: transport.live, update: update)
        update(progress.snapshot)
        // Read only the three selected credentials, and never write them into the report/store.
        var credentials: [UUID: String] = [:]
        for item in check.activeModels {
            try Task.checkCancellation()
            do {
                guard let secret = try transport.credential(item), !secret.isEmpty else { throw ProviderFailure.authorization }
                credentials[item.id] = secret
            } catch { progress.set(item.id, .failed, error: error); return progress.snapshot }
        }
        try Task.checkCancellation()
        let savedCredentials = credentials
        let fusion = check.activeModels.first { $0.purpose == .textFusion }!
        let budget = ConnectionRequestBudget()
        let review = GPTReviewSession(timeout: .seconds(30), maximumOutputTokens: ConnectionCheckLimits.maximumOutputTokens,
            onReady: { progress.set(fusion.id, .accountAccepted) },
            factory: { BudgetedReviewSocket(underlying: try transport.socket($0), budget: budget) },
            fallback: { evidence, prefix, context, item, key in
                try budget.reserve()
                return try await transport.fallback(evidence, prefix, context, item, key)
            })
        var dependencies = RecognitionPipelineDependencies.live
        dependencies.observeLanguage = { _ in } // Synthetic checks must not train the usage profile.
        dependencies.credential = { savedCredentials[$0.id] }
        let selectedModels = check.activeModels
        dependencies.streaming = { provider in
            guard let item = selectedModels.first(where: { $0.provider == provider }) else { throw ProviderFailure.authorization }
            let client = try transport.streaming(provider, { progress.set(item.id, .accountAccepted) })
            return ObservedConnectionProvider(underlying: client, progress: progress)
        }
        dependencies.makeReviewClient = nil
        dependencies.makeReviewClientWithFailure = nil
        dependencies.maximumLiveReviews = 1
        dependencies.arbitrate = { evidence, prefix, context, item, key in
            do {
                progress.set(item.id, .connecting)
                let result = try await review.review(evidence: evidence, prefix: prefix, context: context, configuration: item, credential: key)
                progress.set(item.id, .receiving)
                return result
            } catch { progress.set(item.id, .failed, error: error); throw error }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-connection-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk(); try journal.append(pcm); try journal.closeChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: journal.durableFrames)
        let ticket = try await store.beginFusionRecognition(recordingID: record.id)
        try Task.checkCancellation()
        let session = MultiRecognitionSession(store: store, ticket: ticket, configuration: check, dependencies: dependencies, finalizationTimeout: deadline)
        let began = Date()
        let watchdog = Task { do { try await Task.sleep(for: deadline); session.cancel(); await review.cancel() } catch {} }
        defer { watchdog.cancel() }
        do {
            try await withTaskCancellationHandler {
                let clock = ContinuousClock(), audioStart = ContinuousClock.now
                for offset in stride(from: 0, to: pcm.count, by: 3200) {
                    try Task.checkCancellation()
                    guard !session.isComplete else { break }
                    let end = min(offset + 3200, pcm.count)
                    session.append(pcm.subdata(in: offset..<end))
                    if paced {
                        // Keep one audio clock: scheduling delays must not accumulate
                        // once per block and consume the bounded check before EOS.
                        // PCM is 16 kHz mono Int16; include the shorter final block.
                        let elapsedAudio = Duration.nanoseconds(Int64(end) * 1_000_000_000 / 32_000)
                        try await clock.sleep(until: audioStart.advanced(by: elapsedAudio), tolerance: .zero)
                    }
                }
                try await store.finishRecording(id: record.id)
                session.finish(); await session.wait()
                try Task.checkCancellation()
            } onCancel: { session.cancel(); Task { await review.cancel() } }
        } catch {
            session.cancel(); await review.cancel(); await session.wait(); try? await store.close()
            throw error
        }
        await review.cancel()
        var report = progress.snapshot
        let runs = try await store.modelRuns(recordingID: record.id)
        let candidates = try await store.recognitionCandidates(recordingID: record.id)
        let final = try await store.recording(id: record.id)
        for index in report.services.indices {
            let id = report.services[index].id
            let own = runs.filter { $0.ticket.configurationID == id }
            // Live evidence can be superseded while GPT is running. The last EOS
            // run, not every historical preview run, owns the connection outcome.
            let completed = own.last?.state == .completed
            let candidateCompleted = id == fusion.id || candidates.contains { $0.run.configurationID == id && $0.isComplete && !$0.text.isEmpty }
            if completed && candidateCompleted { report.services[index].state = .verified; report.services[index].code = nil; report.services[index].message = nil }
            else if report.services[index].state != .failed {
                report.services[index].state = .failed; report.services[index].code = "incomplete_response"
                report.services[index].message = "检查未取得完整结果；可保留设置，处理连接后重新检查。"
            }
        }
        report.usage = try await store.modelUsage(recordingID: record.id)
        report.runs = runs
        report.pipelineCompleted = final?.recognitionState == .completed && !(final?.text.isEmpty ?? true)
        report.transcript = final?.text ?? ""
        report.elapsedSeconds = Date().timeIntervalSince(began); report.reviewRequests = budget.count
        report.message = report.pipelineCompleted ? "合成语音已完成接收、融合和定稿。识别准确率尚未评估。" : "检查尚未完整通过；本机识别仍可使用。"
        try await store.close()
        update(report)
        return report
    }
}
