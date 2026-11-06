import Foundation

/// AssemblyAI v3 WebSocket adapter. Provider results are evidence, not authorized input.
public struct AssemblyAIStreamingProvider: StreamingASRProvider {
    public init() {}

    public func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
                    emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        guard configuration.provider == .assemblyAI else { throw ProviderFailure.configuration("Not an AssemblyAI model") }
        try configuration.validate()
        guard !credential.isEmpty else { throw ProviderFailure.authorization }
        let host = configuration.region == "eu" ? "streaming.eu.assemblyai.com" : "streaming.assemblyai.com"
        var parts = URLComponents()
        parts.scheme = "wss"
        parts.host = host
        parts.path = "/v3/ws"
        parts.queryItems = [
            URLQueryItem(name: "speech_model", value: configuration.model),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "encoding", value: "pcm_s16le")
        ]
        guard let url = parts.url else { throw ProviderFailure.configuration("Invalid streaming endpoint") }
        var request = URLRequest(url: url)
        request.setValue(credential, forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 4_000_000
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }

        // The receive loop remains active while audio is being transmitted.
        let receiver = Task {
            var turns: [Int: (text: String, words: [ProviderToken], end: Double, final: Bool)] = [:]
            var receivedTermination = false
            while !Task.isCancelled {
                let message: URLSessionWebSocketTask.Message
                do { message = try await socket.receive() }
                catch { if receivedTermination { return }; throw ProviderFailure.connection }
                let object = try ProviderJSON.object(message)
                guard let type = object["type"] as? String else { throw ProviderFailure.protocolViolation("event-type") }
                if type == "Termination" { receivedTermination = true; return }
                if type == "Begin" { continue }
                if type == "Error" { throw ProviderFailure.protocolViolation("server-error") }
                guard type == "Turn" else { continue }
                let order = object["turn_order"] as? Int ?? 0
                let text = object["transcript"] as? String ?? ""
                let isFinal = object["end_of_turn"] as? Bool ?? false
                let words = Self.parseWords(object["words"])
                let end = words.last?.endSeconds ?? ((object["end"] as? Double ?? 0) / 1000)
                turns[order] = (text, words, end, isFinal)
                let ordered = turns.sorted { $0.key < $1.key }.map(\.value)
                let merged = ordered.map(\.text).joined(separator: " ")
                let stable = ordered.prefix(while: \.final).map(\.text).joined(separator: " ")
                let event = ProviderTranscriptEvent(
                    text: merged, stableUTF16Length: stable.utf16.count,
                    audioEndSeconds: max(0, ordered.map(\.end).max() ?? 0),
                    timingGranularity: "utterance", language: nil,
                    isComplete: false, requestID: object["session_id"] as? String)
                try await emit(event)
            }
        }
        do {
            for await pcm in audio {
                try Task.checkCancellation()
                guard pcm.count % 2 == 0 else { throw ProviderFailure.protocolViolation("pcm-alignment") }
                if !pcm.isEmpty { try await socket.send(.data(pcm)) }
            }
            try await socket.send(.string("{\"type\":\"Terminate\"}"))
            try await receiver.value
        } catch {
            receiver.cancel()
            throw error
        }
    }

    public static func parseWords(_ raw: Any?) -> [ProviderToken] {
        guard let words = raw as? [[String: Any]] else { return [] }
        return words.compactMap { item in
            guard let text = item["text"] as? String,
                  let start = item["start"] as? Double,
                  let end = item["end"] as? Double,
                  start >= 0, end >= start else { return nil }
            return ProviderToken(text: text, startSeconds: start / 1000, endSeconds: end / 1000,
                                 isFinal: true, rawConfidence: item["confidence"] as? Double)
        }
    }
}
