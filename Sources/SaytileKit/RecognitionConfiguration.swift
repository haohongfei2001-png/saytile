import Foundation

public enum RecognitionPurpose: String, Codable, Sendable, CaseIterable {
    case chineseASR, englishASR, multilingualASR, textFusion, audioReview, finalASR
    public var label: String {
        switch self {
        case .chineseASR: "音频专家 A"; case .englishASR: "音频专家 B"; case .multilingualASR: "可选音频专家"
        case .textFusion: "AI 精确融合"; case .audioReview: "疑难原音复听"; case .finalASR: "高精度定稿"
        }
    }
    public var isStreaming: Bool { [.chineseASR, .englishASR, .multilingualASR].contains(self) }
}
public enum CloudProvider: String, Codable, Sendable, CaseIterable {
    case qwenMessage, assemblyAI, soniox, meta, elevenLabsRealtime, elevenLabsFile, openAITranscription, openAIResponses, gemini
    public var label: String {
        switch self {
        case .qwenMessage: "阿里云 Qwen Message"; case .assemblyAI: "AssemblyAI Streaming"; case .soniox: "Soniox"
        case .meta: "Meta Muse Voice"
        case .elevenLabsRealtime: "ElevenLabs Realtime"; case .elevenLabsFile: "ElevenLabs 文件识别"
        case .openAITranscription: "OpenAI 转写"; case .openAIResponses: "OpenAI Responses"; case .gemini: "Google Gemini 音频"
        }
    }
    public var isStreaming: Bool { [.qwenMessage, .assemblyAI, .soniox, .meta].contains(self) }
    public var defaultModel: String {
        switch self {
        case .qwenMessage: "qwen-audio-3.1-asr-flash-message"
        case .assemblyAI: "universal-3-6-pro"
        case .soniox: "stt-rt-v6"
        case .meta: "muse-voice-transcribe-1.0"
        case .openAIResponses: "gpt-6-astra"
        case .gemini: "gemini-3.8-flash"
        case .elevenLabsFile: "scribe_v2"
        case .openAITranscription: "gpt-transcribe"
        case .elevenLabsRealtime: ""
        }
    }

    public func supports(_ purpose: RecognitionPurpose) -> Bool {
        // Retain the persisted enum value, but do not offer an adapter whose
        // automatic segment commits cannot establish whole-session completion.
        if self == .elevenLabsRealtime { return false }
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
    /// Opaque account-authorization identity. Never derived from credential bytes.
    /// Legacy configurations decode missing values as nil; successful key changes
    /// rotate this value so saved audio cannot silently move to another account.
    public var credentialGeneration: UUID?
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
                reasoningEffort: String = "high", reasoningMode: String = "standard", credentialGeneration: UUID? = nil) {
        self.id = id; self.purpose = purpose; self.provider = provider; self.model = model
        self.enabled = enabled; self.cloudConsent = cloudConsent; self.region = region
        self.credentialGeneration = credentialGeneration
        self.workspaceID = workspaceID; self.context = context; self.audioHourRate = audioHourRate
        self.inputMillionTokenRate = inputMillionTokenRate; self.outputMillionTokenRate = outputMillionTokenRate; self.currency = currency
        self.reasoningEffort = reasoningEffort; self.reasoningMode = reasoningMode
    }
    public mutating func resetForProviderChange() {
        cloudConsent = false
        model = provider.defaultModel
        region = provider == .qwenMessage ? "cn-beijing" : "global"
        workspaceID = ""
        audioHourRate = nil; inputMillionTokenRate = nil; outputMillionTokenRate = nil
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
    public func validateForCloud(allowSingleExpertBaseline: Bool = false) throws {
        guard cloudEnabled else { return }
        let active = enabledModels
        guard Set(active.map(\.id)).count == active.count else {
            throw ProviderFailure.configuration("模型配置身份重复，请为每项配置使用独立身份。")
        }
        let experts = active.filter { $0.purpose.isStreaming }
        let fusion = active.filter { $0.purpose == .textFusion }
        let unsupported = active.filter { !$0.purpose.isStreaming && $0.purpose != .textFusion }
        guard unsupported.isEmpty else {
            throw ProviderFailure.configuration("V1 仅启用双语音频专家与一个 GPT-6 融合核心；独立音频复听/文件定稿不属于默认识别链。")
        }
        guard fusion.count == 1, fusion[0].provider == .openAIResponses, fusion[0].model == "gpt-6-astra" else {
            throw ProviderFailure.configuration("必须且只能配置一个 GPT-6 Astra 文本融合核心。")
        }
        if allowSingleExpertBaseline {
            guard experts.count == 1, experts[0].purpose.isStreaming else {
                throw ProviderFailure.configuration("单专家对照必须恰好启用一个实时 ASR（包括多语言模型），并保留唯一 GPT-6 核心。")
            }
        } else {
            guard experts.count >= 2, experts.count <= 3,
                  experts.filter({ $0.purpose == .chineseASR }).count == 1,
                  experts.filter({ $0.purpose == .englishASR }).count >= 1,
                  experts.filter({ $0.purpose == .englishASR }).count <= 2,
                  experts.filter({ $0.purpose == .multilingualASR }).count <= 1 else {
                throw ProviderFailure.configuration("默认方案需要一位中文专家、一位英文专家；最多额外增加一位挑战模型。")
            }
        }
        for item in active {
            try item.validate()
            guard item.cloudConsent else { throw ProviderFailure.configuration("请先授权\(item.purpose.label)的云端处理。") }
            if item.provider == .qwenMessage,
               [item.context, topicContext].filter({ !$0.isEmpty }).joined(separator: "\n").count > 400 {
                throw ProviderFailure.configuration("Qwen Message 的模型提示与当前话题合计最多 400 字，请缩短后应用。")
            }
        }
    }
    // IDs survive updates, so an upgrade does not detach existing Keychain credentials.
    private static var recommendedModels: [ModelConfiguration] { [
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000001")!, purpose: .chineseASR,
              provider: .qwenMessage, model: "qwen-audio-3.1-asr-flash-message", region: "cn-beijing"),
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000002")!, purpose: .englishASR,
              provider: .assemblyAI, model: "universal-3-6-pro"),
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000004")!, purpose: .textFusion,
              provider: .openAIResponses, model: "gpt-6-astra"),
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000003")!, purpose: .multilingualASR,
              provider: .soniox, model: "stt-rt-v6", enabled: false),
        .init(id: UUID(uuidString: "A71E0001-0000-4000-8000-000000000007")!, purpose: .englishASR,
              provider: .meta, model: "muse-voice-transcribe-1.0", enabled: false)
    ] }
    public static func load(from preferences: UserDefaults) -> Self {
        guard let data = preferences.data(forKey: "multiASRConfigurationV1"),
              var config = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        // Migrate the former multi-arbiter/audio-review defaults without deleting Keychain
        // items. Preserve the stable GPT-6 configuration ID so an existing Key remains usable.
        config.inputMode = .highestQuality
        for index in config.models.indices where [.audioReview, .finalASR].contains(config.models[index].purpose) {
            config.models[index].enabled = false
            config.models[index].cloudConsent = false
        }
        // Keep custom provider/model/ID metadata intact. Unsupported legacy choices need
        // explicit reconfiguration; migration must never silently replace a custom model.
        let fusionIndices = config.models.indices.filter { config.models[$0].purpose == .textFusion }
        let chosen = fusionIndices.first { config.models[$0].enabled &&
            config.models[$0].provider == .openAIResponses && config.models[$0].model == "gpt-6-astra" }
        for index in fusionIndices where index != chosen {
            config.models[index].enabled = false
            config.models[index].cloudConsent = false
        }
        if chosen == nil { config.cloudEnabled = false }
        return config
    }
    public func save(to preferences: UserDefaults) throws {
        preferences.set(try JSONEncoder().encode(self), forKey: "multiASRConfigurationV1")
    }
}
