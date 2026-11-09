import Foundation

/// Only a Saytile user session is ever presented to this endpoint.
public struct HostedAccess: Sendable, Equatable {
    let origin: URL
    let bearer: String
    let expiry: Date
}
public enum HostedRoute: Sendable, Equatable {
    case byok, local, connected(HostedAccess)
}

final class HostedNetwork: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = URLSession(configuration: .ephemeral, delegate: HostedNetwork(), delegateQueue: nil)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    static func request(_ url: URL, bearer: String? = nil, payload: [String: String]? = nil, key: String? = nil) async throws -> Data {
        var r = URLRequest(url: url); r.timeoutInterval = url.lastPathComponent == "review" ? 90 : 12
        if let bearer { r.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        if let key { r.setValue(key, forHTTPHeaderField: "apikey") }
        if let payload {
            r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONEncoder().encode(payload)
        }
        let (data, response) = try await shared.data(for: r)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 401: throw ProviderFailure.authorization
        case 403: throw ProviderFailure.permission
        case 429: throw ProviderFailure.rateLimited
        default: throw ProviderFailure.connection
        }
    }
}

final class HostedTransport: StreamingASRProvider, @unchecked Sendable {
    let access: HostedAccess
    let ticket: RecognitionTicket
    private struct Evidence { let text: String; let stable: Int; let complete: Bool; let proof: String }
    private let lock = NSLock()
    private var proofs: [Evidence] = []
    init(_ access: HostedAccess, _ ticket: RecognitionTicket) { self.access = access; self.ticket = ticket }
    static var configuration: RecognitionConfiguration {
        var config = RecognitionConfiguration()
        config.cloudEnabled = true; config.languagePreference = .chinese
        config.models = [
            .init(id: UUID(uuidString:"01DE0000-0000-4000-8000-000000000001")!, purpose:.chineseASR, provider:.qwenMessage,
                  model:CloudProvider.qwenMessage.defaultModel, cloudConsent:true, region:"cn-beijing", workspaceID:"saytile-hosted"),
            .init(id: UUID(uuidString:"01DE0000-0000-4000-8000-000000000002")!, purpose:.textFusion, provider:.openAIResponses,
                  model:CloudProvider.openAIResponses.defaultModel, cloudConsent:true)]
        return config
    }
    var dependencies: RecognitionPipelineDependencies {
        .init(credential: { _ in "hosted-session" }, streaming: { provider in
            guard provider == .qwenMessage else { throw ProviderFailure.permission }; return self
        }, transcribe: { _,_,_ in throw ProviderFailure.permission }, arbitrate: { evidence,_,_,_,_ in
            try await self.review(evidence)
        }, listen: { _,_,_ in throw ProviderFailure.permission }, maximumLiveReviews:15)
    }
    private func review(_ evidence: [ReviewEvidence]) async throws -> (PrecisionReviewDecision, PrecisionReviewUsage) {
        guard evidence.count == 1, let e = evidence.first,
              let proof = lock.withLock({ proofs.last { $0.text.utf8.elementsEqual(e.text.utf8) && $0.stable == e.stableUTF16Length && $0.complete == e.isComplete }?.proof }) else { throw ProviderFailure.incomplete }
        let start = Date()
        let data = try await HostedNetwork.request(access.origin.appending(path:"v1/review"), bearer:access.bearer,
            payload:["candidateID":e.candidateID.uuidString, "text":e.text, "proof":proof])
        struct Usage: Decodable { let input_tokens: Int?; let output_tokens: Int?; let request_id: String? }
        struct Reply: Decodable { let decision: PrecisionReviewDecision; let usage: Usage }
        let reply = try JSONDecoder().decode(Reply.self, from:data)
        return (reply.decision, .init(requestID:reply.usage.request_id,inputTokens:reply.usage.input_tokens,
            outputTokens:reply.usage.output_tokens,elapsedSeconds:Date().timeIntervalSince(start)))
    }
    private func envelope(_ socket: URLSessionWebSocketTask) async throws -> [String:Any] {
        let data: Data
        switch try await socket.receive() { case .data(let value): data=value
        case .string(let s): data=Data(s.utf8); @unknown default: throw ProviderFailure.connection }
        guard let json = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw ProviderFailure.incomplete }
        return json
    }
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        guard access.expiry > Date(), var url = URLComponents(url:access.origin.appending(path:"v1/stream"),resolvingAgainstBaseURL:false) else { throw ProviderFailure.authorization }
        url.scheme = access.origin.scheme == "http" ? "ws" : "wss"
        guard let endpoint = url.url else { throw ProviderFailure.connection }
        var r = URLRequest(url:endpoint); r.timeoutInterval = 100
        let id = ticket.recordingID.uuidString
        for (key,value) in ["Authorization":"Bearer " + access.bearer, "X-Saytile-Recording":id,
                            "X-Saytile-Epoch":String(ticket.audioEpoch),"X-Saytile-Consent":"zh-v1"] { r.setValue(value,forHTTPHeaderField:key) }
        let socket = HostedNetwork.shared.webSocketTask(with:r); socket.maximumMessageSize = 262144; socket.resume()
        defer { socket.cancel(with:.goingAway,reason:nil) }
        try await withTaskCancellationHandler {
            let start = try await envelope(socket)
            var codec = QwenMessageCodec(taskID:id)
            guard let event = start["event"] as? [String:Any] else { throw ProviderFailure.connection }
            _ = try codec.consume(event)
            guard codec.hasStarted else { throw ProviderFailure.incomplete }
            try await withThrowingTaskGroup(of:Void.self) { group in
                group.addTask {
                    do {
                        var index: UInt32 = 0
                        for await chunk in audio { try Task.checkCancellation(); var n = index.bigEndian
                            var frame = withUnsafeBytes(of:&n){ Data($0) }; frame.append(chunk)
                            try await socket.send(.data(frame)); index += 1
                        }
                        try await socket.send(.string("eos"))
                    } catch { socket.cancel(with:.goingAway,reason:nil); throw error }
                }
                do {
                    var expected = 1
                    while !codec.isComplete {
                        let msg = try await envelope(socket)
                        guard msg["recording"] as? String == id, msg["epoch"] as? Int64 == ticket.audioEpoch,
                              msg["sequence"] as? Int == expected, let ev = msg["event"] as? [String:Any],
                              let proof = msg["proof"] as? String else { throw ProviderFailure.incomplete }
                        expected += 1
                        if let value = try codec.consume(ev) {
                            lock.withLock { proofs.append(.init(text:value.text,stable:value.stableUTF16Length,complete:value.isComplete,proof:proof))
                                if proofs.count > 64 { proofs.removeFirst() } }
                            try await emit(value)
                        }
                    }
                    try await group.waitForAll()
                } catch { group.cancelAll(); socket.cancel(with:.goingAway,reason:nil); throw error }
            }
        } onCancel: { socket.cancel(with:.goingAway,reason:nil) }
    }
}
