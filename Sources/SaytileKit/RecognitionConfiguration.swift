import Foundation

public enum RecognitionPurpose: String, Codable, Sendable, CaseIterable {
    case chineseASR, englishASR, multilingualASR, textFusion, audioReview, finalASR
    public var label: String {
        switch self {
        case .chineseASR: "中文专家"; case .englishASR: "英文专家"; case .multilingualASR: "中英混合复核"
        case .textFusion: "AI 精确融合"; case .audioReview: "疑难原音复听"; case .finalASR: "高精度定稿"
        }
    }
    public var isStreaming: Bool { [.chineseASR, .englishASR, .multilingualASR].contains(self) }
}
public enum CloudProvider: String, Codable, Sendable, CaseIterable {
    case qwenMessage, assemblyAI, soniox, elevenLabsRealtime, elevenLabsFile, openAITranscription, openAIResponses, gemini
    public var label: String {
        switch self {
        case .qwenMessage: "阿里云 Qwen Message"; case .assemblyAI: "AssemblyAI Streaming"; case .soniox: "Soniox"
        case .elevenLabsRealtime: "ElevenLabs Realtime"; case .elevenLabsFile: "ElevenLabs 文件识别"
        case .openAITranscription: "OpenAI 转写"; case .openAIResponses: "OpenAI Responses"; case .gemini: "Google Gemini 音频"
        }
    }
    public var isStreaming: Bool { [.qwenMessage, .assemblyAI, .soniox, .elevenLabsRealtime].contains(self) }
    public func supports(_ purpose: RecognitionPurpose) -> Bool {
        if purpose.isStreaming { return isStreaming }
        if purpose == .textFusion { return self == .openAIResponses }
        if purpose == .audioReview { return self == .gemini }
        return [.elevenLabsFile, .openAITranscription].contains(self)
    }
}
public enum InputQualityMode: String, Codable, Sendable, CaseIterable {
    case highestQuality, fast
    public var label: String { self == .highestQuality ? "最高质量" : "快速输入" }
}
public struct ModelConfiguration: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var purpose: RecognitionPurpose
    public var provider: CloudProvider
    public var model: String
    public var enabled: Bool
    public var cloudConsent: Bool
    public var region: String
    public var workspaceID: String
    public var context: String
    public var audioHourRate: Double?
    public var inputMillionTokenRate: Double?
    public var outputMillionTokenRate: Double?
    public var currency: String
    public var reasoningEffort: String
    public var reasoningMode: String
    public init(id: UUID = UUID(), purpose: RecognitionPurpose, provider: CloudProvider, model: String,
                enabled: Bool = true, cloudConsent: Bool = false, region: String = "global",
                workspaceID: String = "", context: String = "", audioHourRate: Double? = nil,
                inputMillionTokenRate: Double? = nil, outputMillionTokenRate: Double? = nil, currency: String = "USD",
                reasoningEffort: String = "high", reasoningMode: String = "standard") {
        self.id = id; self.purpose = purpose; self.provider = provider; self.model = model
        self.enabled = enabled; self.cloudConsent = cloudConsent; self.region = region
        self.workspaceID = workspaceID; self.context = context; self.audioHourRate = audioHourRate
        self.inputMillionTokenRate = inputMillionTokenRate; self.outputMillionTokenRate = outputMillionTokenRate; self.currency = currency
        self.reasoningEffort = reasoningEffort; self.reasoningMode = reasoningMode
    }
    public func validate() throws {
        guard provider.supports(purpose), !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              model.count <= 160, model.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw ProviderFailure.configuration("请为\(purpose.label)选择受支持的服务和有效模型。")
        }
        guard context.count <= 16_000 else { throw ProviderFailure.configuration("当前话题上下文过长，请缩短。") }
        guard ["low", "medium", "high", "xhigh", "max"].contains(reasoningEffort),
              ["standard", "pro"].contains(reasoningMode) else { throw ProviderFailure.configuration("推理设置无效。") }
        for rate in [audioHourRate, inputMillionTokenRate, outputMillionTokenRate].compactMap({ $0 }) {
            guard rate.isFinite, rate >= 0 else { throw ProviderFailure.configuration("费用单价须为非负数。") }
        }
        if provider == .qwenMessage {
            guard ["cn-beijing", "ap-southeast-1"].contains(region),
                  !workspaceID.isEmpty, workspaceID.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
                throw ProviderFailure.configuration("Qwen 需要相同地域的 Workspace ID 与 API Key（北京或新加坡）。")
            }
        }
    }
}

public struct RecognitionConfiguration: Codable, Sendable, Equatable {
    public var cloudEnabled = false
    public var inputMode: InputQualityMode = .highestQuality
    public var models: [ModelConfiguration] = []
    /// Session context is deliberately local and explicit; no background document scraping.
    public var topicContext = ""
    public var automaticRecovery = true
    public init() { models = Self.recommendedModels }
    public var enabledModels: [ModelConfiguration] { models.filter(\.enabled) }
    public func validateForCloud() throws {
        guard cloudEnabled else { return }
        let active = enabledModels
        guard Set(active.map(\.id)).count == active.count,
              active.contains(where: { $0.purpose == .chineseASR }),
              active.contains(where: { $0.purpose == .englishASR }) else {
            throw ProviderFailure.configuration("并行方案需要中文和英文专家各一个。")
        }
        for item in active {
            try item.validate()
            guard item.cloudConsent else { throw ProviderFailure.configuration("请先授权\(item.purpose.label)的云端处理。") }
        }
    }
    // IDs survive updates, so an upgrade does not detach existing Keychain credentials.
    private static var recommendedModels: [ModelConfiguration] { [
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000001")!, purpose: .chineseASR,
              provider: .qwenMessage, model: "qwen-audio-3.1-asr-flash-message", region: "cn-beijing"),
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000002")!, purpose: .englishASR,
              provider: .assemblyAI, model: "universal-3-6-pro"),
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000003")!, purpose: .multilingualASR,
              provider: .soniox, model: "stt-rt-v6", enabled: false),
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000004")!, purpose: .textFusion,
              provider: .openAIResponses, model: "gpt-6-astra", enabled: false),
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000005")!, purpose: .audioReview,
              provider: .gemini, model: "gemini-3.8-flash", enabled: false),
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000006")!, purpose: .finalASR,
              provider: .elevenLabsFile, model: "scribe_v2", enabled: false)
    ] }
    public static func load(from preferences: UserDefaults) -> Self {
        guard let data = preferences.data(forKey: "multiASRConfigurationV1"),
              let config = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return config
    }
    public func save(to preferences: UserDefaults) throws {
        preferences.set(try JSONEncoder().encode(self), forKey: "multiASRConfigurationV1")
    }
}
