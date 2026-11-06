import Foundation
import Testing
@testable import SaytileKit

private final class ReviewSocketFixture: GPTReviewSocket, @unchecked Sendable {
    enum Behavior: Sendable { case normal, missSecond, fail, incomplete, unsupported, silent, wrongIdentity, oversized }
    private let lock = NSLock()
    private var sent: [Data] = []
    private var events: [Data] = []
    private var closed = false
    let behavior: Behavior
    let candidateID: UUID
    init(_ behavior: Behavior = .normal, candidateID: UUID) { self.behavior = behavior; self.candidateID = candidateID }
    var requests: [Data] { lock.withLock { sent } }
    var isClosed: Bool { lock.withLock { closed } }
    func send(_ data: Data) async throws {
        try lock.withLock {
            guard !closed else { throw CancellationError() }
            sent.append(data)
            if behavior == .silent || behavior == .unsupported { return }
            let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let lane = root["stream_id"] as! String, id = "resp_\(sent.count)"
            func add(_ value: [String: Any]) throws { events.append(try JSONSerialization.data(withJSONObject: value)) }
            if behavior == .missSecond && sent.count == 2 {
                try add(["type": "error", "stream_id": lane, "error": ["code": "previous_response_not_found"]]); return
            }
            try add(["type": "response.created", "stream_id": lane, "response": ["id": id, "model": "gpt-6-astra"]])
            try add(["type": "response.output_text.delta", "stream_id": lane, "response_id": id, "delta": "{invalid partial JSON"])
            try add(["type": "response.completed", "stream_id": "other-lane", "response": ["id": "wrong"]])
            if behavior == .oversized { events.append(Data(repeating: 32, count: 8_000_001)); return }
            let decision = PrecisionReviewDecision(selections: [.init(candidateID: candidateID, utf16Start: 0, utf16End: 2)], unresolved: false, needsAudioReview: false, reasonCode: "fixture")
            let text = String(decoding: try JSONEncoder().encode(decision), as: UTF8.self)
            let response: [String: Any] = ["id": id, "model": "gpt-6-astra", "status": "completed", "output": [["type": "message", "status": "completed", "content": [["type": "output_text", "text": text]]]]]
            if behavior == .wrongIdentity {
                try add(["type": "response.completed", "stream_id": lane, "response": ["id": "old-response", "status": "completed"]])
            }
            let type = behavior == .fail ? "response.failed" : behavior == .incomplete ? "response.incomplete" : "response.completed"
            try add(["type": type, "stream_id": lane, "response": response])
        }
    }
    func receive() async throws -> Data {
        if behavior == .unsupported { throw GPTSocketFailure.unsupported }
        while true {
            try Task.checkCancellation()
            if isClosed { throw CancellationError() }
            if let value = lock.withLock({ events.isEmpty ? nil : events.removeFirst() }) { return value }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    func close() { lock.withLock { closed = true } }
}

private final class ReviewSocketPool: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ReviewSocketFixture] = []
    var sockets: [ReviewSocketFixture] { lock.withLock { values } }
    func make() -> ReviewSocketFixture {
        lock.withLock {
            let socket = ReviewSocketFixture(candidateID: UUID())
            values.append(socket); return socket
        }
    }
}

@Suite("Persistent single GPT transport, deterministic no-network protocol")
struct GPTReviewSessionTests {
    private var config: ModelConfiguration { .init(purpose: .textFusion, provider: .openAIResponses, model: "gpt-6-astra", cloudConsent: true) }
    private func evidence(_ id: UUID = UUID()) -> ReviewEvidence {
        .init(candidateID: id, provider: "synthetic", model: "synthetic", role: "chineseASR", text: "不要", stableUTF16Length: 2, audioStartSeconds: 0, audioEndSeconds: 1, timingGranularity: "utterance", isComplete: true, sequence: 1)
    }
    private func root(_ data: Data) throws -> [String: Any] { try JSONSerialization.jsonObject(with: data) as! [String: Any] }
    private func payload(_ data: Data) throws -> [String: Any] {
        let input = try root(data)["input"] as! [[String: Any]]
        return try root(Data((input[0]["content"] as! String).utf8))
    }
    @Test func persistentLaneUsesLineageAndManifestDeltasNeverPartialJSON() async throws {
        let item = evidence(), socket = ReviewSocketFixture(candidateID: UUID())
        let client = GPTReviewSession(factory: { _ in socket })
        let configuration = config
        _ = try await client.review(evidence: [item], prefix: "", context: "", configuration: configuration, credential: "synthetic")
        _ = try await client.review(evidence: [item], prefix: "", context: "", configuration: configuration, credential: "synthetic")
        let requests = socket.requests
        #expect(requests.count == 2)
        #expect(try root(requests[0])["stream"] == nil)
        #expect(try root(requests[0])["type"] as? String == "response.create")
        #expect(try root(requests[1])["previous_response_id"] as? String == "resp_1")
        #expect(try root(requests[0])["stream_id"] as? String == root(requests[1])["stream_id"] as? String)
        #expect(try (payload(requests[1])["candidates"] as? [Any])?.isEmpty == true)
        #expect(try (payload(requests[1])["currentManifest"] as? [Any])?.count == 1)
        await client.cancel(); #expect(socket.isClosed)
    }
    @Test func cacheMissReplaysFullAuthoritativeManifestOnce() async throws {
        let item = evidence(), socket = ReviewSocketFixture(.missSecond, candidateID: UUID())
        let client = GPTReviewSession(factory: { _ in socket }), configuration = config
        _ = try await client.review(evidence: [item], prefix: "", context: "", configuration: configuration, credential: "synthetic")
        _ = try await client.review(evidence: [item], prefix: "", context: "", configuration: configuration, credential: "synthetic")
        #expect(socket.requests.count == 3)
        #expect(try root(socket.requests[2])["previous_response_id"] == nil)
        #expect(try (payload(socket.requests[2])["candidates"] as? [Any])?.count == 1)
        await client.cancel()
    }
    @Test(arguments: [ReviewSocketFixture.Behavior.fail, .incomplete, .oversized])
    fileprivate func terminalFailuresAndBufferLimitCannotPublish(behavior: ReviewSocketFixture.Behavior) async throws {
        let socket = ReviewSocketFixture(behavior, candidateID: UUID())
        let client = GPTReviewSession(factory: { _ in socket })
        await #expect(throws: (any Error).self) {
            try await client.review(evidence: [evidence()], prefix: "", context: "", configuration: config, credential: "synthetic")
        }
        #expect(socket.isClosed)
    }
    @Test func oldResponseIdentityIsIgnored() async throws {
        let item = evidence(), socket = ReviewSocketFixture(.wrongIdentity, candidateID: UUID())
        let client = GPTReviewSession(factory: { _ in socket })
        let (_, usage) = try await client.review(evidence: [item], prefix: "", context: "", configuration: config, credential: "synthetic")
        #expect(usage.requestID == "resp_1")
        await client.cancel()
    }
    @Test func timeoutClosesSocketAndDoesNotUseFallback() async throws {
        let socket = ReviewSocketFixture(.silent, candidateID: UUID())
        let client = GPTReviewSession(timeout: .milliseconds(20), factory: { _ in socket }, fallback: { _, _, _, _, _ in
            Issue.record("Timeout must not silently invoke another request"); throw ProviderFailure.connection
        })
        await #expect(throws: (any Error).self) {
            try await client.review(evidence: [evidence()], prefix: "", context: "", configuration: config, credential: "synthetic")
        }
        #expect(socket.isClosed)
    }
    @Test func explicitCancelPreventsFutureRequests() async throws {
        let socket = ReviewSocketFixture(.silent, candidateID: UUID())
        let client = GPTReviewSession(factory: { _ in socket })
        let task = Task { try await client.review(evidence: [evidence()], prefix: "", context: "", configuration: config, credential: "synthetic") }
        while socket.requests.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        await client.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        await #expect(throws: CancellationError.self) {
            try await client.review(evidence: [evidence()], prefix: "", context: "", configuration: config, credential: "synthetic")
        }
    }
    @Test func unsupportedSocketFallsBackOnlyToSameConfiguredGPT() async throws {
        let socket = ReviewSocketFixture(.unsupported, candidateID: UUID())
        let client = GPTReviewSession(factory: { _ in socket }, fallback: { _, _, _, configuration, _ in
            #expect(configuration.model == "gpt-6-astra")
            return (.init(selections: [], unresolved: true, needsAudioReview: false, reasonCode: "fallback-fixture"), .init(elapsedSeconds: 0))
        })
        let (decision, _) = try await client.review(evidence: [evidence()], prefix: "", context: "", configuration: config, credential: "synthetic")
        #expect(decision.reasonCode == "fallback-fixture")
        #expect(socket.isClosed)
    }
    @Test func credentialAndConfigurationChangesInvalidateConnectionCache() async throws {
        let pool = ReviewSocketPool(), item = evidence()
        let client = GPTReviewSession(factory: { _ in pool.make() })
        var configuration = config
        _ = try await client.review(evidence: [item], prefix: "", context: "", configuration: configuration, credential: "synthetic-first")
        _ = try await client.review(evidence: [item], prefix: "", context: "", configuration: configuration, credential: "synthetic-changed")
        configuration.context = "different authorized context"
        _ = try await client.review(evidence: [item], prefix: "", context: "", configuration: configuration, credential: "synthetic-changed")
        #expect(pool.sockets.count == 3)
        #expect(pool.sockets[0].isClosed && pool.sockets[1].isClosed)
        for socket in pool.sockets {
            #expect(try root(socket.requests[0])["previous_response_id"] == nil)
            #expect(try payload(socket.requests[0])["resetEvidence"] as? Bool == true)
        }
        await client.cancel()
    }

}
