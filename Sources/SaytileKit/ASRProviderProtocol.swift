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
    case configuration(String), authorization, permission, regionMismatch, quota, rateLimited, connection, protocolViolation(String), incomplete, cancelled
    public var errorDescription: String? {
        switch self {
        case .configuration(let reason): return reason
        case .authorization: return "服务鉴权或权限失败；请检查此模型的 API Key 和开通状态。"
        case .permission: return "此账户无权调用所选模型；请检查模型开通状态与 API Key 权限。"
        case .regionMismatch: return "服务地域或工作空间不匹配；请使用同一地域的 Workspace 与 API Key。"
        case .quota: return "服务配额或余额不足；原音继续保存。"
        case .rateLimited: return "服务暂时限流；稍后自动恢复，原音继续保存。"
        case .connection: return "模型连接中断或超时；可从原音恢复。"
        case .protocolViolation(let code): return "模型响应不完整或不受支持（\(code)）。"
        case .incomplete: return "模型未完成定稿；候选和原音已保留。"
        case .cancelled: return "本次模型运行已取消；原音保留。"
        }
    }
    public var canRetryAutomatically: Bool {
        switch self { case .authorization, .permission, .regionMismatch, .quota, .configuration, .protocolViolation: false; default: true }
    }
    public var diagnosticCode: String {
        switch self {
        case .configuration: "invalid_configuration"
        case .authorization: "authorization_failed"
        case .permission: "permission_denied"
        case .regionMismatch: "region_workspace_mismatch"
        case .quota: "quota_exhausted"
        case .rateLimited: "rate_limited"
        case .connection: "connection_failed"
        case .protocolViolation: "protocol_incompatible"
        case .incomplete: "incomplete_response"
        case .cancelled: "cancelled"
        }
    }
    public var minimumRetryDelay: TimeInterval { if case .rateLimited = self { 60 } else { 0 } }
    /// Never include arbitrary provider error bodies, URLs or Authorization in diagnostics.
    public static func http(_ code: Int) -> ProviderFailure {
        switch code {
        case 400, 404, 422: .configuration("服务型号、接口或请求参数不受支持；请检查此模型的配置。")
        case 401: .authorization
        case 403: .permission
        case 402: .quota
        case 429: .rateLimited
        default: .connection
        }
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
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ProviderFailure.protocolViolation("json") }
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
    var recordingID: UUID { get }
    var isComplete: Bool { get }
    func append(_ data: Data)
    func finish()
    func cancel()
    func wait() async
}

/// Internal endpoint seam for protocol-level loopback tests. Normal app configuration
/// never reads this URL; the production URLSession and codecs are unchanged.
enum ProviderTestEndpoint {
    static func validate(_ endpoint: URL, schemes: Set<String>) throws -> URL {
        guard let parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme, schemes.contains(scheme),
              let host = parts.host, ["127.0.0.1", "::1", "[::1]"].contains(host),
              let port = parts.port, (1...65535).contains(port),
              parts.user == nil, parts.password == nil, parts.fragment == nil else {
            throw ProviderFailure.configuration("协议测试只允许显式本机回环地址。")
        }
        return endpoint
    }
    static func applying(_ endpoint: URL, to request: URLRequest) throws -> URLRequest {
        guard let original = request.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }),
              var replacement = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ProviderFailure.configuration("协议测试地址无效。")
        }
        _ = try validate(endpoint, schemes: ["ws", "wss", "http", "https"])
        let names = Set((original.queryItems ?? []).map(\.name))
        guard !(replacement.queryItems ?? []).contains(where: { names.contains($0.name) }) else {
            throw ProviderFailure.configuration("协议测试不得覆盖正式请求参数。")
        }
        replacement.queryItems = (original.queryItems ?? []) + (replacement.queryItems ?? [])
        guard let url = replacement.url else { throw ProviderFailure.configuration("协议测试地址无效。") }
        var result = request; result.url = url
        return result
    }
}
