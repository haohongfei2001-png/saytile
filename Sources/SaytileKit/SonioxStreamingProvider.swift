import Foundation

public struct SonioxStreamingProvider: StreamingASRProvider {
    public init() {}

    public func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
                    emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        let referenceID = UUID().uuidString
        let request = try SonioxStreamingCodec.request(configuration: configuration, credential: credential)
        let start = try SonioxStreamingCodec.startMessage(configuration: configuration, referenceID: referenceID)
        let session = ChineseASRWebSocket.makeSession()
        let socket = session.webSocketTask(with: request)
        defer { socket.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            socket.resume()
            // Soniox has no documented ready event. Completion of the ordered start
            // write is its audio-send gate, unlike Qwen's task-started acknowledgement.
            try await ChineseASRWebSocket.send(.string(start), to: socket)
            try await ChineseASRWebSocket.stream(audio: audio, socket: socket, endMessage: "",
                                                decoder: SonioxStreamingCodec(referenceID: referenceID), emit: emit)
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }
}

struct SonioxStreamingCodec: ChineseASRFrameDecoder {
    private struct Piece: Sendable {
        var text: String
        var token: ProviderToken?
    }
    let referenceID: String
    private var final: [Piece] = []
    private var partial: [Piece] = []
    private var processedSeconds: Double = 0
    private var requestID: String?
    private(set) var isComplete = false
    init(referenceID: String) { self.referenceID = referenceID }

    static func request(configuration: ModelConfiguration, credential: String) throws -> URLRequest {
        try configuration.validate()
        guard configuration.provider == .soniox, configuration.model.hasPrefix("stt-rt-"),
              configuration.region == "global" else {
            throw ProviderFailure.configuration("Soniox 实时适配器需要 stt-rt 系列模型及 global 服务地域。")
        }
        try ChineseASRWebSocket.validateCredential(credential)
        var request = URLRequest(url: URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!, timeoutInterval: 20)
        // JSON api_key authentication is deprecated; never put credentials in payloads.
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        return request
    }
    static func startMessage(configuration: ModelConfiguration, referenceID: String) throws -> String {
        var object: [String: Any] = [
            "model": configuration.model, "audio_format": "pcm_s16le", "sample_rate": 16_000,
            "num_channels": 1, "language_hints": ["zh", "en"], "language_hints_strict": false,
            "enable_language_identification": true, "enable_endpoint_detection": true,
            "client_reference_id": referenceID
        ]
        if !configuration.context.isEmpty { object["context"] = ["text": configuration.context] }
        return try ProviderJSON.string(object)
    }

    mutating func consume(_ object: [String: Any]) throws -> ProviderTranscriptEvent? {
        guard !isComplete else { throw ProviderFailure.protocolViolation("soniox_after_finished") }
        if let code = object["error_code"] as? Int {
            if code == 400 { throw ProviderFailure.configuration("Soniox 模型或请求参数不受支持，请检查模型配置。") }
            throw ProviderFailure.http(code)
        }
        if let id = object["request_id"] as? String { requestID = id }
        guard let incoming = object["tokens"] as? [[String: Any]] else {
            throw ProviderFailure.protocolViolation("soniox_tokens")
        }
        var newFinal: [Piece] = [], newPartial: [Piece] = []
        var sawPartial = false
        for item in incoming {
            guard let text = item["text"] as? String else { throw ProviderFailure.protocolViolation("soniox_token") }
            // Endpoint/manual-finalization control tokens are not spoken words.
            if text == "<end>" || text == "<fin>" { continue }
            guard let isFinal = item["is_final"] as? Bool,
                  item["translation_status"] as? String != "translation" else {
                throw ProviderFailure.protocolViolation("soniox_source_token")
            }
            if text.isEmpty { continue }
            if isFinal && sawPartial { throw ProviderFailure.protocolViolation("soniox_final_order") }
            if !isFinal { sawPartial = true }
            var token: ProviderToken?
            if let start = ChineseASRWebSocket.seconds(item["start_ms"]),
               let end = ChineseASRWebSocket.seconds(item["end_ms"]) {
                guard end >= start else { throw ProviderFailure.protocolViolation("soniox_timing") }
                let confidence = (item["confidence"] as? NSNumber)?.doubleValue
                token = .init(text: text, startSeconds: start, endSeconds: end, isFinal: isFinal,
                              language: item["language"] as? String,
                              rawConfidence: confidence.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil })
            }
            let piece = Piece(text: text, token: token)
            if isFinal { newFinal.append(piece) } else { newPartial.append(piece) }
        }
        let finished = object["finished"] as? Bool == true
        if finished && (!newPartial.isEmpty || (!partial.isEmpty && newFinal.isEmpty)) {
            throw ProviderFailure.incomplete
        }
        final += newFinal
        // Protocol guarantee: each final token arrives once; each response replaces
        // the entire non-final tail. Repeated partials therefore never duplicate text.
        partial = newPartial
        processedSeconds = max(processedSeconds, ChineseASRWebSocket.seconds(object["total_audio_proc_ms"]) ?? 0)
        isComplete = finished
        let pieces = final + partial
        let text = pieces.map(\.text).joined()
        let tokens = pieces.compactMap(\.token)
        let fullyTimed = tokens.count == pieces.count
        let languages = Set(tokens.compactMap(\.language))
        // Whole-stream candidates share recording origin zero with the other experts;
        // retain any leading silence exclusively in the original token timestamps.
        return .init(text: text, stableUTF16Length: final.reduce(0) { $0 + $1.text.utf16.count },
                     audioStartSeconds: 0,
                     audioEndSeconds: max(processedSeconds, tokens.map(\.endSeconds).max() ?? 0),
                     timingGranularity: fullyTimed ? "token" : "utterance",
                     language: languages.count == 1 ? languages.first : (languages.count > 1 ? "mixed" : nil),
                     isComplete: finished, requestID: requestID ?? referenceID, tokens: fullyTimed ? tokens : [])
    }
}
