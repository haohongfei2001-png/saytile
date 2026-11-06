import Foundation

/// PCM is always 16 kHz mono signed little-endian Int16. Capture persists it first.
/// Every runner owns a separate stream; a slow vendor cannot stall any other vendor.
public struct ProviderTranscriptEvent: Sendable, Equatable {
    public var text: String
    public var stableUTF16Length: Int
    public var audioStartSeconds: Double
    public var audioEndSeconds: Double
    public var timingGranularity: String
    public var language: String?
    public var isComplete: Bool
    public var requestID: String?
    public var tokens: [ProviderToken]
    public init(text: String, stableUTF16Length: Int = 0, audioStartSeconds: Double = 0,
                audioEndSeconds: Double, timingGranularity: String = "utterance",
                language: String? = nil, isComplete: Bool = false, requestID: String? = nil,
                tokens: [ProviderToken] = []) {
        self.text = text; self.stableUTF16Length = stableUTF16Length
        self.audioStartSeconds = audioStartSeconds; self.audioEndSeconds = audioEndSeconds
        self.timingGranularity = timingGranularity; self.language = language
        self.isComplete = isComplete; self.requestID = requestID; self.tokens = tokens
    }
}
public struct ProviderToken: Sendable, Equatable {
    public var text: String
    public var startSeconds: Double
    public var endSeconds: Double
    public var isFinal: Bool
    public var language: String?
    public var rawConfidence: Double?
    public init(text: String, startSeconds: Double, endSeconds: Double, isFinal: Bool,
                language: String? = nil, rawConfidence: Double? = nil) {
        self.text = text; self.startSeconds = startSeconds; self.endSeconds = endSeconds
        self.isFinal = isFinal; self.language = language; self.rawConfidence = rawConfidence
    }
}

public enum ProviderFailure: LocalizedError, Sendable {
    case configuration(String), authorization, quota, connection, protocolViolation(String), incomplete, cancelled
    public var errorDescription: String? {
        switch self {
        case .configuration(let reason): return reason
        case .authorization: return "服务鉴权或权限失败；请检查此模型的 API Key 和开通状态。"
        case .quota: return "服务配额或余额不足；原音继续保存。"
        case .connection: return "模型连接中断或超时；可从原音恢复。"
        case .protocolViolation(let code): return "模型响应不完整或不受支持（\(code)）。"
        case .incomplete: return "模型未完成定稿；候选和原音已保留。"
        case .cancelled: return "本次模型运行已取消；原音保留。"
        }
    }
    public var canRetryAutomatically: Bool {
        switch self { case .authorization, .quota, .configuration: false; default: true }
    }
    /// Never include arbitrary provider error bodies, URLs or Authorization in diagnostics.
    public static func http(_ code: Int) -> ProviderFailure {
        switch code { case 401, 403: .authorization; case 402, 429: .quota; default: .connection }
    }
}

struct ProviderJSON {
    static func string(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw ProviderFailure.protocolViolation("json") }
        return text
    }
    static func object(_ message: URLSessionWebSocketTask.Message) throws -> [String: Any] {
        let data: Data
        switch message { case .string(let value): data = Data(value.utf8); case .data(let value): data = value; @unknown default: throw ProviderFailure.protocolViolation("frame") }
        guard data.count <= 4_000_000,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderFailure.protocolViolation("json") }
        return object
    }
}

/// Protocol adapters own provider-specific request/response schemas. There is no universal
/// "OpenAI-compatible" assumption. Implementations must serialize EOS after all audio.
public protocol StreamingASRProvider: Sendable {
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws
}

public protocol RecognitionSession: AnyObject, Sendable {
    var isComplete: Bool { get }
    func append(_ data: Data)
    func finish()
    func cancel()
    func wait() async
}
