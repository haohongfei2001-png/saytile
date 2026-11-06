import Foundation
import CryptoKit

/// One socket per recording/generation. No audio, tools, or second model is sent here.
protocol GPTReviewSocket: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close()
}
enum GPTSocketFailure: Error { case unsupported, cacheMiss, timeout, busy, limit }

final class NativeGPTReviewSocket: GPTReviewSocket, @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    init(credential: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        session = URLSession(configuration: configuration)
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/responses")!)
        request.setValue("Bearer " + credential, forHTTPHeaderField: "Authorization")
        task = session.webSocketTask(with: request)
        task.maximumMessageSize = 8_000_000
        task.resume()
    }
    func send(_ data: Data) async throws {
        guard let text = String(data: data, encoding: .utf8) else { throw ProviderFailure.incomplete }
        do { try await task.send(.string(text)) }
        catch { try classify(error) }
    }
    func receive() async throws -> Data {
        do {
            switch try await task.receive() {
            case .data(let data): return data
            case .string(let text): return Data(text.utf8)
            @unknown default: throw ProviderFailure.incomplete
            }
        } catch {
            try classify(error)
            throw error
        }
    }
    private func classify(_ error: Error) throws {
        if let response = task.response as? HTTPURLResponse {
            if [404, 405, 426, 501].contains(response.statusCode) { throw GPTSocketFailure.unsupported }
            if !(200..<300).contains(response.statusCode), response.statusCode != 101 { throw ProviderFailure.http(response.statusCode) }
        }
        throw error
    }
    func close() { task.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
    deinit { close() }
}

actor GPTReviewSession {
    typealias Factory = @Sendable (String) throws -> any GPTReviewSocket
    typealias Fallback = @Sendable ([ReviewEvidence], String, String, ModelConfiguration, String) async throws -> (PrecisionReviewDecision, PrecisionReviewUsage)
    private let factory: Factory
    private let fallback: Fallback
    private let timeout: Duration
    private let lane = UUID().uuidString
    private var socket: (any GPTReviewSocket)?
    private var identity: Data?
    private var previousResponseID: String?
    private var manifest: [UUID: ReviewEvidence] = [:]
    private var turns = 0
    private var busy = false
    private var cancelled = false
    init(timeout: Duration = .seconds(120), factory: @escaping Factory = { NativeGPTReviewSocket(credential: $0) },
         fallback: @escaping Fallback = {
             try await PrecisionReviewClient().arbitrate(evidence: $0, confirmedPrefix: $1, context: $2, configuration: $3, credential: $4)
         }) {
        self.factory = factory; self.fallback = fallback; self.timeout = timeout
    }
    func cancel() { cancelled = true; reset() }
    private func reset() {
        socket?.close(); socket = nil; previousResponseID = nil
        manifest.removeAll(); turns = 0; identity = nil
    }
    func review(evidence: [ReviewEvidence], prefix: String, context: String,
                configuration: ModelConfiguration, credential: String) async throws -> (PrecisionReviewDecision, PrecisionReviewUsage) {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        guard !busy else { throw GPTSocketFailure.busy }
        busy = true; defer { busy = false }
        guard configuration.cloudConsent, configuration.provider == .openAIResponses,
              configuration.model == "gpt-6-astra", !credential.isEmpty else {
            reset(); throw ProviderFailure.authorization
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let fingerprint = Data(SHA256.hash(data: try encoder.encode(configuration) + Data(credential.utf8)))
        if identity != fingerprint || turns >= 32 { reset(); identity = fingerprint }
        let began = Date()
        do {
            // A cache miss has one bounded full-context retry. No replay of an output/dispatch.
            for attempt in 0..<2 {
                if socket == nil { socket = try factory(credential) }
                let connection = socket!
                let body = try request(evidence: evidence, prefix: prefix, context: context, configuration: configuration)
                do {
                    let response = try await Self.exchange(connection, body: body, lane: lane, timeout: timeout)
                    try Task.checkCancellation()
                    guard !cancelled else { throw CancellationError() }
                    let (decision, input, output) = try PrecisionReviewClient.decodeResponse(response)
                    let object = try JSONSerialization.jsonObject(with: response) as? [String: Any]
                    guard let id = object?["id"] as? String, !id.isEmpty else { throw ProviderFailure.incomplete }
                    previousResponseID = id; manifest = Dictionary(uniqueKeysWithValues: evidence.map { ($0.candidateID, $0) }); turns += 1
                    return (decision, .init(requestID: id, inputTokens: input, outputTokens: output, elapsedSeconds: Date().timeIntervalSince(began)))
                } catch GPTSocketFailure.cacheMiss where attempt == 0 {
                    previousResponseID = nil; manifest.removeAll(); turns = 0
                }
            }
            throw GPTSocketFailure.cacheMiss
        } catch GPTSocketFailure.unsupported {
            reset()
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            // Only an unsupported WebSocket endpoint falls back, to the SAME GPT HTTP API.
            return try await fallback(evidence, prefix, context, configuration, credential)
        } catch { reset(); throw error }
    }
    private func request(evidence: [ReviewEvidence], prefix: String, context: String, configuration: ModelConfiguration) throws -> Data {
        let changes = previousResponseID == nil ? evidence : evidence.filter { manifest[$0.candidateID] != $0 }
        let body = try PrecisionReviewClient.requestBody(evidence: changes, confirmedPrefix: prefix, context: context, configuration: configuration)
        var root = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        var input = root["input"] as! [[String: Any]]
        var payload = try JSONSerialization.jsonObject(with: Data((input[0]["content"] as! String).utf8)) as! [String: Any]
        payload["currentManifest"] = evidence.map { ["candidateID": $0.candidateID.uuidString, "sequence": $0.sequence ?? 0] as [String: Any] }
        payload["resetEvidence"] = previousResponseID == nil
        payload["manifestRule"] = "Only IDs in currentManifest are valid. All omitted prior candidate IDs are invalidated. candidates contains changed evidence; reuse unchanged IDs only. Return exact current IDs and spans."
        input[0]["content"] = try ProviderJSON.string(payload)
        root["input"] = input; root["type"] = "response.create"; root["stream_id"] = lane
        root.removeValue(forKey: "stream")
        if let previousResponseID { root["previous_response_id"] = previousResponseID }
        let result = try JSONSerialization.data(withJSONObject: root)
        guard result.count <= 1_000_000, evidence.count <= 64 else { throw GPTSocketFailure.limit }
        return result
    }
    private nonisolated static func exchange(_ socket: any GPTReviewSocket, body: Data, lane: String, timeout: Duration) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await socket.send(body)
                    var responseID: String?, bytes = 0
                    for _ in 0..<8192 {
                        try Task.checkCancellation()
                        let data = try await socket.receive(); bytes += data.count
                        guard data.count <= 8_000_000, bytes <= 16_000_000 else { throw GPTSocketFailure.limit }
                        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { throw ProviderFailure.incomplete }
                        let eventLane = event["stream_id"] as? String
                        if type == "error", eventLane == nil { throw ProviderFailure.connection }
                        guard eventLane == lane else { continue }
                        if type == "error" {
                            let error = event["error"] as? [String: Any]
                            if error?["code"] as? String == "previous_response_not_found" { throw GPTSocketFailure.cacheMiss }
                            throw ProviderFailure.incomplete
                        }
                        let response = event["response"] as? [String: Any]
                        let id = response?["id"] as? String ?? event["response_id"] as? String
                        if type == "response.created" || type == "response.in_progress" {
                            if responseID == nil { responseID = id }
                        }
                        guard let responseID, id == responseID else { continue }
                        if type == "response.failed" || type == "response.incomplete" { throw ProviderFailure.incomplete }
                        if type == "response.completed", let response { return try JSONSerialization.data(withJSONObject: response) }
                        // Delta JSON is evidence-in-progress, never a user-visible transcript.
                    }
                    throw GPTSocketFailure.limit
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    socket.close()
                    throw GPTSocketFailure.timeout
                }
                defer { group.cancelAll() }
                do { return try await group.next()! }
                catch GPTSocketFailure.cacheMiss { throw GPTSocketFailure.cacheMiss }
                catch { socket.close(); throw error }
            }
        } onCancel: { socket.close() }
    }
}
