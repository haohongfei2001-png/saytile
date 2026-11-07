import Foundation
import CryptoKit

/// One socket per recording/generation. No audio, tools, or second model is sent here.
protocol GPTReviewSocket: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close()
}
enum GPTSocketFailure: Error { case unsupported, cacheMiss, reconnect, timeout, busy, limit }

/// Diagnostics use only recognized codes/status, never arbitrary server messages.
enum GPTServiceError {
    static func failure(_ object: [String: Any], status: Int? = nil) -> ProviderFailure {
        let error = object["error"] as? [String: Any] ?? object
        switch (error["code"] as? String ?? error["type"] as? String ?? "").lowercased() {
        case "invalid_api_key", "authentication_error": return .authorization
        case "model_not_found", "permission_denied", "insufficient_permissions": return .permission
        case "insufficient_quota", "billing_hard_limit_reached": return .quota
        case "rate_limit_exceeded", "rate_limit_error": return .rateLimited
        case "server_error", "internal_error": return .connection
        default:
            if let status = status ?? object["status"] as? Int { return .http(status) }
            return .protocolViolation("gpt-error")
        }
    }
}

final class NativeGPTReviewSocket: GPTReviewSocket, @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    convenience init(credential: String) {
        self.init(credential: credential, endpoint: URL(string: "wss://api.openai.com/v1/responses")!, timeout: 120)
    }
    /// Protocol tests replace only the peer; the URLSession transport stays identical.
    convenience init(credential: String, testEndpoint: URL, timeout: TimeInterval = 1) throws {
        let endpoint = try ProviderTestEndpoint.validate(testEndpoint, schemes: ["ws", "wss"])
        self.init(credential: credential, endpoint: endpoint, timeout: timeout)
    }
    private init(credential: String, endpoint: URL, timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        session = URLSession(configuration: configuration)
        var request = URLRequest(url: endpoint)
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
        let native = error as NSError
        if native.domain == NSPOSIXErrorDomain,
           [POSIXErrorCode.ENOTCONN, .ECONNRESET, .ECONNABORTED, .EPIPE, .ENETRESET].contains(where: { Int($0.rawValue) == native.code }) {
            throw GPTSocketFailure.reconnect
        }
        throw error
    }
    func close() { task.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
    deinit { close() }
}

struct ReviewFailureObserver: Sendable {
    let callback: @Sendable (Error) -> Void
    init(_ callback: @escaping @Sendable (Error) -> Void) { self.callback = callback }
}

actor GPTReviewSession {
    typealias Factory = @Sendable (String) throws -> any GPTReviewSocket
    typealias Fallback = @Sendable ([ReviewEvidence], String, String, ModelConfiguration, String) async throws -> (PrecisionReviewDecision, PrecisionReviewUsage)
    private let factory: Factory
    private let fallback: Fallback
    private let timeout: Duration
    private let onReady: @Sendable () -> Void
    private let onFailure: @Sendable (Error) -> Void
    private let maximumOutputTokens: Int?
    private let lane = UUID().uuidString
    private var socket: (any GPTReviewSocket)?
    private var identity: Data?
    private var fallbackIdentity: Data?
    private var previousResponseID: String?
    private var manifest: [UUID: ReviewEvidence] = [:]
    private var turns = 0
    private var busy = false
    private var cancelled = false
    init(timeout: Duration = .seconds(120), maximumOutputTokens: Int? = nil, onReady: @escaping @Sendable () -> Void = {},
         onFailure: @escaping @Sendable (Error) -> Void = { _ in },
         factory: @escaping Factory = { NativeGPTReviewSocket(credential: $0) },
         fallback: Fallback? = nil) {
        self.factory = factory
        self.fallback = fallback ?? {
            try await PrecisionReviewClient(maximumOutputTokens: maximumOutputTokens).arbitrate(
                evidence: $0, confirmedPrefix: $1, context: $2, configuration: $3, credential: $4)
        }
        self.timeout = timeout; self.onReady = onReady; self.onFailure = onFailure; self.maximumOutputTokens = maximumOutputTokens
    }
    func cancel() { cancelled = true; reset() }
    private func reset() {
        socket?.close(); socket = nil; previousResponseID = nil
        manifest.removeAll(); turns = 0; identity = nil; fallbackIdentity = nil
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
            if fallbackIdentity == fingerprint {
                return try await reviewViaHTTP(evidence: evidence, prefix: prefix, context: context, configuration: configuration, credential: credential)
            }
            // A cache miss has one bounded full-context retry. No replay of an output/dispatch.
            for attempt in 0..<2 {
                try Task.checkCancellation()
                guard !cancelled else { throw CancellationError() }
                // Validate the bounded request before opening an authenticated socket.
                let body = try request(evidence: evidence, prefix: prefix, context: context, configuration: configuration)
                if socket == nil { socket = try factory(credential) }
                let connection = socket!
                do {
                    let response = try await Self.exchange(connection, body: body, lane: lane, model: configuration.model, timeout: timeout, onReady: onReady)
                    try Task.checkCancellation()
                    guard !cancelled else { throw CancellationError() }
                    let (decision, input, output, cachedInput, reasoning) = try PrecisionReviewClient.decodeResponse(response)
                    let object = try JSONSerialization.jsonObject(with: response) as? [String: Any]
                    guard let id = object?["id"] as? String, !id.isEmpty else { throw ProviderFailure.incomplete }
                    previousResponseID = id; manifest = Dictionary(uniqueKeysWithValues: evidence.map { ($0.candidateID, $0) }); turns += 1
                    return (decision, .init(requestID: id, inputTokens: input, outputTokens: output,
                                            cachedInputTokens: cachedInput, reasoningTokens: reasoning,
                                            elapsedSeconds: Date().timeIntervalSince(began)))
                } catch GPTSocketFailure.cacheMiss where attempt == 0 {
                    previousResponseID = nil; manifest.removeAll(); turns = 0
                } catch GPTSocketFailure.reconnect where attempt == 0 {
                    try Task.checkCancellation()
                    reset(); identity = fingerprint
                } catch let error as URLError where attempt == 0 && [.networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains(error.code) {
                    try Task.checkCancellation()
                    reset(); identity = fingerprint
                }
            }
            throw GPTSocketFailure.cacheMiss
        } catch GPTSocketFailure.unsupported {
            reset(); identity = fingerprint; fallbackIdentity = fingerprint
            // Remember unsupported transport for this exact configuration/credential.
            // Repeated failed upgrades must not consume the connection-check budget.
            do {
                return try await reviewViaHTTP(evidence: evidence, prefix: prefix, context: context, configuration: configuration, credential: credential)
            } catch { onFailure(Self.failoverFailure(error)); throw error }
        } catch { reset(); onFailure(Self.failoverFailure(error)); throw error }
    }
    private nonisolated static func failoverFailure(_ error: Error) -> Error {
        if let failure = error as? ProviderFailure { return failure }
        if error is GPTSocketFailure { return ProviderFailure.connection }
        if let error = error as? URLError, error.code != .cancelled { return ProviderFailure.connection }
        return error
    }
    private func reviewViaHTTP(evidence: [ReviewEvidence], prefix: String, context: String,
                               configuration: ModelConfiguration, credential: String) async throws -> (PrecisionReviewDecision, PrecisionReviewUsage) {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        // Same model, complete current evidence, no previous socket lineage.
        let result = try await fallback(evidence, prefix, context, configuration, credential)
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        onReady()
        return result
    }
    private func request(evidence: [ReviewEvidence], prefix: String, context: String, configuration: ModelConfiguration) throws -> Data {
        let changes = previousResponseID == nil ? evidence : evidence.filter { manifest[$0.candidateID] != $0 }
        let body = try PrecisionReviewClient.requestBody(evidence: changes, confirmedPrefix: prefix, context: context, configuration: configuration, maximumOutputTokens: maximumOutputTokens)
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
    private nonisolated static func exchange(_ socket: any GPTReviewSocket, body: Data, lane: String, model: String,
                                             timeout: Duration, onReady: @escaping @Sendable () -> Void) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await socket.send(body)
                    var responseID: String?, bytes = 0, ready = false
                    for _ in 0..<8192 {
                        try Task.checkCancellation()
                        let data = try await socket.receive(); bytes += data.count
                        guard data.count <= 8_000_000, bytes <= 16_000_000 else { throw GPTSocketFailure.limit }
                        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { throw ProviderFailure.protocolViolation("gpt-event-json") }
                        let eventLane = event["stream_id"] as? String
                        if type == "error", eventLane == nil || eventLane == lane {
                            let error = event["error"] as? [String: Any]
                            if error?["code"] as? String == "previous_response_not_found" { throw GPTSocketFailure.cacheMiss }
                            if error?["code"] as? String == "websocket_connection_limit_reached" { throw GPTSocketFailure.reconnect }
                            throw GPTServiceError.failure(event)
                        }
                        guard eventLane == lane else { continue }
                        let response = event["response"] as? [String: Any]
                        let id = response?["id"] as? String ?? event["response_id"] as? String
                        if type == "response.created" || type == "response.in_progress" {
                            guard let id, !id.isEmpty, response?["model"] as? String == model else {
                                throw ProviderFailure.protocolViolation("gpt-applied-model")
                            }
                            if responseID == nil { responseID = id }
                            if responseID == id, !ready { ready = true; onReady() }
                        }
                        guard let responseID, id == responseID else { continue }
                        if type == "response.failed" {
                            guard let response, response["error"] as? [String: Any] != nil else { throw ProviderFailure.incomplete }
                            throw GPTServiceError.failure(response)
                        }
                        if type == "response.incomplete" { throw ProviderFailure.incomplete }
                        if type == "response.completed", let response {
                            guard response["model"] as? String == model else { throw ProviderFailure.protocolViolation("gpt-applied-model") }
                            return try JSONSerialization.data(withJSONObject: response)
                        }
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
