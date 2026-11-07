import Foundation
import CryptoKit
import Testing
@testable import SaytileKit

private let simulatorCredential = "simulator-fixture-credential"
private let protocolSimulationEnabled = ProcessInfo.processInfo.environment["SAYTILE_PROTOCOL_BASE_URL"] != nil

private struct ProtocolPeer: Sendable {
    let base: URL
    let id = UUID().uuidString
    init() throws {
        base = try #require(ProcessInfo.processInfo.environment["SAYTILE_PROTOCOL_BASE_URL"].flatMap(URL.init(string:)))
        _ = try ProviderTestEndpoint.validate(base, schemes: ["http"])
    }
    func url(_ service: String, fault: String = "normal", websocket: Bool = true) -> URL {
        var parts = URLComponents(url: base.appendingPathComponent(service), resolvingAgainstBaseURL: false)!
        parts.scheme = websocket ? "ws" : "http"
        parts.queryItems = [.init(name: "case", value: id), .init(name: "fault", value: fault)]
        return parts.url!
    }
    func snapshot() async throws -> [String: Any] {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: base.appendingPathComponent("state/" + id))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func reviewClient(fault: String = "normal", timeout: Duration = .seconds(2), onReady: @escaping @Sendable () -> Void = {}) -> GPTReviewSession {
        let websocket = url("responses", fault: fault), http = url("responses", fault: fault, websocket: false)
        return GPTReviewSession(timeout: timeout, maximumOutputTokens: 4096, onReady: onReady,
            factory: { try NativeGPTReviewSocket(credential: $0, testEndpoint: websocket, timeout: 2) },
            fallback: { try await PrecisionReviewClient(testEndpoint: http, timeout: 2, maximumOutputTokens: 4096)
                .arbitrate(evidence: $0, confirmedPrefix: $1, context: $2, configuration: $3, credential: $4) })
    }
}
private actor NetworkEvents {
    var values: [ProviderTranscriptEvent] = []
    func append(_ value: ProviderTranscriptEvent) { values.append(value) }
}
private final class ReadyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func mark() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

/// Explicit opt-in: ordinary unit runs never launch a peer or use network credentials.
/// scripts/test-protocol-simulator.sh supplies the loopback server for this suite.
@Suite("Real URLSession loopback protocol integration", .serialized, .enabled(if: protocolSimulationEnabled))
struct ProtocolNetworkIntegrationTests {
    private func configuration() -> RecognitionConfiguration {
        var value = RecognitionConfiguration(); value.cloudEnabled = true
        for index in value.models.indices {
            value.models[index].cloudConsent = true
            if value.models[index].provider == .qwenMessage { value.models[index].workspaceID = "synthetic-workspace" }
        }
        return value
    }
    private var pcm: Data { Data((0..<32_000).map { UInt8($0 % 251) }) }
    private var gpt: ModelConfiguration { configuration().enabledModels.first { $0.purpose == .textFusion }! }
    private func evidence(text: String, id: UUID = UUID(), sequence: Int64 = 1) -> ReviewEvidence {
        .init(candidateID: id, provider: "synthetic", model: "synthetic", role: "chineseASR", text: text,
              stableUTF16Length: text.utf16.count, audioStartSeconds: 0, audioEndSeconds: 1,
              timingGranularity: "utterance", isComplete: true, sequence: sequence)
    }
    private func input(_ bytes: Data) -> AsyncStream<Data> {
        AsyncStream { continuation in
            for index in stride(from: 0, to: bytes.count, by: 3200) {
                continuation.yield(bytes.subdata(in: index..<min(index + 3200, bytes.count)))
            }
            continuation.finish()
        }
    }
    private func runASR(_ service: String, peer: ProtocolPeer, fault: String = "normal", events: NetworkEvents) async throws {
        let value = configuration().enabledModels.first { $0.provider == (service == "qwen" ? .qwenMessage : .assemblyAI) }!
        let provider: any StreamingASRProvider = service == "qwen"
            ? try QwenMessageProvider(testEndpoint: peer.url(service, fault: fault), timeout: 0.6)
            : try AssemblyStreamingProvider(testEndpoint: peer.url(service, fault: fault), timeout: 0.6)
        try await provider.run(audio: input(pcm), configuration: value, credential: simulatorCredential) { await events.append($0) }
    }

    @Test func twoProductionASRClientsReceiveIdenticalWholePCMAndEOS() async throws {
        let peer = try ProtocolPeer(), chinese = NetworkEvents(), english = NetworkEvents()
        async let a: Void = runASR("qwen", peer: peer, events: chinese)
        async let b: Void = runASR("assembly", peer: peer, events: english)
        try await a; try await b
        for values in [await chinese.values, await english.values] {
            #expect(values.contains { !$0.isComplete && $0.text.contains("支付") })
            #expect(Set(values.map(\.text)).count >= 3)
            #expect(values.last?.isComplete == true)
            #expect(values.last?.text == "请不要支付15元，send the report。")
        }
        try await Task.sleep(for: .milliseconds(40))
        let state = try await peer.snapshot()
        let connections = try #require(state["connections"] as? [[String: Any]])
        let hash = SHA256.hash(data: pcm).map { String(format: "%02x", $0) }.joined()
        #expect(connections.count == 2)
        #expect(connections.allSatisfy { $0["pcm_bytes"] as? Int == pcm.count && $0["sha256"] as? String == hash && $0["eos"] as? Bool == true })
        #expect((state["violations"] as? [String])?.isEmpty == true)
    }

    @Test func productionTwentyMillisecondFramesAndShortTailKeepExactPCM() async throws {
        let peer = try ProtocolPeer(), chinese = NetworkEvents(), english = NetworkEvents()
        let bytes = pcm + Data(repeating: 7, count: 198) // 6.1875 ms final tail: no padding.
        let config = configuration()
        @Sendable func receive(_ service: String, events: NetworkEvents) async throws {
            let item = config.enabledModels.first { $0.provider == (service == "qwen" ? .qwenMessage : .assemblyAI) }!
            let provider: any StreamingASRProvider = service == "qwen"
                ? try QwenMessageProvider(testEndpoint: peer.url(service), timeout: 2)
                : try AssemblyStreamingProvider(testEndpoint: peer.url(service), timeout: 2)
            let (stream, continuation) = AsyncStream<Data>.makeStream()
            let producer = Task {
                defer { continuation.finish() }
                for offset in stride(from: 0, to: bytes.count, by: 640) {
                    try Task.checkCancellation()
                    continuation.yield(bytes.subdata(in: offset..<min(offset + 640, bytes.count)))
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
            defer { producer.cancel() }
            try await provider.run(audio: stream, configuration: item, credential: simulatorCredential) { await events.append($0) }
            try await producer.value
        }
        async let a: Void = receive("qwen", events: chinese)
        async let b: Void = receive("assembly", events: english)
        try await a; try await b
        #expect(await chinese.values.last?.isComplete == true)
        #expect(await english.values.last?.isComplete == true)
        try await Task.sleep(for: .milliseconds(40))
        let state = try await peer.snapshot(), connections = try #require(state["connections"] as? [[String: Any]])
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(connections.count == 2)
        #expect(connections.allSatisfy { $0["pcm_bytes"] as? Int == bytes.count && $0["sha256"] as? String == hash && $0["eos"] as? Bool == true })
        let qwen = try #require(connections.first { $0["provider"] as? String == "qwen" })
        #expect(qwen["blocks"] as? [Int] == Array(repeating: 640, count: 50) + [198])
        let assembly = try #require(connections.first { $0["provider"] as? String == "assembly" })
        #expect((assembly["blocks"] as? [Int])?.allSatisfy { (640...32_000).contains($0) } == true)
        #expect((state["violations"] as? [String])?.isEmpty == true)
        print("PROTOCOL_PCM case=\(peer.id) input_frames=50x640+198 bytes=\(bytes.count) no_padding=true scope=SIMULATED_PROTOCOL_NOT_LIVE_CLOUD")
    }

    @Test(arguments: ["qwen", "assembly"], ["duplicate", "delay"])
    func repeatedAndDelayedNetworkEventsDoNotDuplicateTranscript(service: String, fault: String) async throws {
        let peer = try ProtocolPeer(), events = NetworkEvents()
        try await runASR(service, peer: peer, fault: fault, events: events)
        #expect(await events.values.last?.text == "请不要支付15元，send the report。")
        #expect(await events.values.last?.isComplete == true)
    }

    @Test(arguments: ["qwen", "assembly"], ["auth", "quota", "disconnect", "malformed", "missing_final", "timeout", "server_error"])
    func networkFailuresCannotBecomeFinalTranscripts(service: String, fault: String) async throws {
        let peer = try ProtocolPeer(), events = NetworkEvents()
        do {
            try await runASR(service, peer: peer, fault: fault, events: events)
            Issue.record("Fault must be an explicit failed run: \(service)/\(fault)")
        } catch {
            #expect(!error.localizedDescription.contains("DO_NOT_SURFACE_SECRET"))
            if fault == "auth" { #expect((error as? ProviderFailure)?.diagnosticCode == "authorization_failed") }
            if fault == "quota" { #expect((error as? ProviderFailure)?.diagnosticCode == "quota_exhausted") }
        }
        #expect(await events.values.allSatisfy { !$0.isComplete })
    }

    @Test(arguments: ["normal", "old_events", "cache_miss", "reconnect", "limit"])
    func persistentGPTUsesActualEvidenceDeltasAndBoundedRebuild(fault: String) async throws {
        let peer = try ProtocolPeer(), ready = ReadyCounter()
        let client = peer.reviewClient(fault: fault, onReady: ready.mark)
        let first = evidence(text: "请不要支付15元。")
        let (one, _) = try await client.review(evidence: [first], prefix: "", context: "", configuration: gpt, credential: simulatorCredential)
        #expect(one.selections.first?.candidateID == first.candidateID)
        // Unchanged identity is retained from the server's actual connection cache.
        let (two, _) = try await client.review(evidence: [first], prefix: "", context: "", configuration: gpt, credential: simulatorCredential)
        #expect(two.selections.first?.candidateID == first.candidateID)
        let corrected = evidence(text: "请不要支付15元，send the report。")
        let (three, _) = try await client.review(evidence: [corrected], prefix: "", context: "", configuration: gpt, credential: simulatorCredential)
        #expect(three.selections.first?.candidateID == corrected.candidateID)
        #expect(three.selections.first?.utf16End == corrected.text.utf16.count)
        #expect(ready.value >= 3)
        await client.cancel()
        let state = try await peer.snapshot(), requests = try #require(state["gpt_requests"] as? [[String: Any]])
        #expect(requests.count == (fault == "cache_miss" || fault == "reconnect" || fault == "limit" ? 4 : 3))
        #expect(requests[1]["previous_response_id"] as? String != nil)
        #expect(requests[1]["candidate_count"] as? Int == 0)
        if requests.count == 4 {
            #expect(requests[2]["reset"] as? Bool == true)
            #expect(requests[2]["previous_response_id"] is NSNull)
            #expect(requests[2]["candidate_count"] as? Int == 1)
        }
        #expect(requests.allSatisfy { $0["max_output_tokens"] as? Int == 4096 })
        #expect((state["violations"] as? [String])?.isEmpty == true)
    }

    @Test func unsupportedGPTWebSocketUsesSameModelProductionHTTPStreamingClient() async throws {
        let peer = try ProtocolPeer(), client = peer.reviewClient(fault: "unsupported"), item = evidence(text: "不要发送😀")
        let (decision, usage) = try await client.review(evidence: [item], prefix: "", context: "", configuration: gpt, credential: simulatorCredential)
        #expect(decision.selections.first?.candidateID == item.candidateID)
        #expect(decision.selections.first?.utf16End == item.text.utf16.count)
        #expect(usage.requestID?.hasPrefix("resp_http_") == true)
        _ = try await client.review(evidence: [item], prefix: "", context: "", configuration: gpt, credential: simulatorCredential)
        await client.cancel()
        let state = try await peer.snapshot(), requests = try #require(state["gpt_requests"] as? [[String: Any]])
        #expect(requests.count == 2 && requests.allSatisfy { $0["transport"] as? String == "http" })
        #expect(state["unsupported_upgrades"] as? Int == 1)
        #expect(requests.allSatisfy { $0["max_output_tokens"] as? Int == 4096 })
        #expect((state["violations"] as? [String])?.isEmpty == true)
    }

    @Test(arguments: ["auth", "quota", "rate_limit", "malformed", "invalid_schema", "wrong_model", "timeout", "server_error", "stream_quota", "failed_rate"])
    func GPTFailureIsExplicitAndDoesNotFallbackToAnotherModel(fault: String) async throws {
        let peer = try ProtocolPeer(), client = peer.reviewClient(fault: fault, timeout: .milliseconds(200))
        do {
            _ = try await client.review(evidence: [evidence(text: "不是50元。")], prefix: "", context: "", configuration: gpt, credential: simulatorCredential)
            Issue.record("GPT fault must fail: \(fault)")
        } catch {
            #expect(!error.localizedDescription.contains("DO_NOT_SURFACE_SECRET"))
            let expected = ["auth": "authorization_failed", "quota": "quota_exhausted", "rate_limit": "rate_limited", "wrong_model": "protocol_incompatible", "invalid_schema": "protocol_incompatible", "malformed": "protocol_incompatible", "stream_quota": "quota_exhausted", "failed_rate": "rate_limited"]
            if let code = expected[fault] { #expect((error as? ProviderFailure)?.diagnosticCode == code) }
        }
        await client.cancel()
        let requests = try await peer.snapshot()["gpt_requests"] as? [[String: Any]] ?? []
        #expect(requests.allSatisfy { $0["transport"] as? String == "websocket" })
    }

    @Test(arguments: ["quota", "rate_limit", "auth", "server_error", "malformed", "stream_quota", "failed_rate"])
    func HTTPErrorPayloadProducesSafeSpecificDiagnostic(fault: String) async throws {
        // This checks provider error categories, not the short timeout fault path.
        // Full native CI shares CPU with hundreds of SQLite/lifecycle test tasks.
        let peer = try ProtocolPeer(), client = try PrecisionReviewClient(testEndpoint: peer.url("responses", fault: fault, websocket: false), timeout: 10, maximumOutputTokens: 4096)
        do {
            _ = try await client.arbitrate(evidence: [evidence(text: "不是50元")], confirmedPrefix: "", context: "", configuration: gpt, credential: simulatorCredential)
            Issue.record("HTTP service error must fail")
        } catch {
            let expected = ["auth": "authorization_failed", "quota": "quota_exhausted", "rate_limit": "rate_limited", "server_error": "connection_failed", "malformed": "protocol_incompatible", "stream_quota": "quota_exhausted", "failed_rate": "rate_limited"]
            let native = error as NSError
            #expect((error as? ProviderFailure)?.diagnosticCode == expected[fault], "Unexpected transport failure domain=\(native.domain), code=\(native.code)")
            #expect(!error.localizedDescription.contains("DO_NOT_SURFACE_SECRET"))
        }
    }

    @Test(arguments: [0, 128_001])
    func invalidConnectionCheckBudgetFailsBeforeOpeningSocket(cap: Int) async throws {
        let peer = try ProtocolPeer(), opened = ReadyCounter(), endpoint = peer.url("responses")
        let client = GPTReviewSession(maximumOutputTokens: cap, factory: {
            opened.mark()
            return try NativeGPTReviewSocket(credential: $0, testEndpoint: endpoint)
        })
        await #expect(throws: ProviderFailure.self) {
            try await client.review(evidence: [evidence(text: "不要")], prefix: "", context: "", configuration: gpt, credential: simulatorCredential)
        }
        #expect(opened.value == 0)
        await client.cancel()
    }

    @Test func cancellingActualGPTSocketClosesPeerBeforeAnyFinalSelection() async throws {
        let peer = try ProtocolPeer(), client = peer.reviewClient(fault: "cancel"), item = evidence(text: "不要发送")
        let config = gpt
        let task = Task { try await client.review(evidence: [item], prefix: "", context: "", configuration: config, credential: simulatorCredential) }
        for _ in 0..<50 {
            if let requests = try await peer.snapshot()["gpt_requests"] as? [Any], !requests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel(); await client.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        try await Task.sleep(for: .milliseconds(40))
        let connections = try await peer.snapshot()["connections"] as? [[String: Any]] ?? []
        #expect(connections.contains { $0["provider"] as? String == "gpt" && $0["closed"] as? Bool == true })
    }

    @Test(arguments: ["normal", "unsupported", "churn", "each_reconnect"])
    func actualConnectionWizardBackendUsesBoundedProductionNetwork(fault: String) async throws {
        let peer = try ProtocolPeer(), config = configuration(), sample = try CloudConnectionVerifier.bundledSample()
        var transport = CloudConnectionTransport()
        transport.live = false
        transport.credential = { _ in simulatorCredential }
        transport.streaming = { provider, ready in
            let asrFault = fault == "churn" ? "churn" : "normal"
            if provider == .qwenMessage { return try QwenMessageProvider(testEndpoint: peer.url("qwen", fault: asrFault), timeout: 3, onReady: ready) }
            return try AssemblyStreamingProvider(testEndpoint: peer.url("assembly", fault: asrFault), timeout: 3, onReady: ready)
        }
        let gptFault = ["unsupported", "each_reconnect"].contains(fault) ? fault : "normal"
        transport.socket = { try NativeGPTReviewSocket(credential: $0, testEndpoint: peer.url("responses", fault: gptFault), timeout: 3) }
        transport.fallback = { try await PrecisionReviewClient(testEndpoint: peer.url("responses", fault: gptFault, websocket: false), timeout: 3, maximumOutputTokens: 4096)
            .arbitrate(evidence: $0, confirmedPrefix: $1, context: $2, configuration: $3, credential: $4) }
        let report = try await CloudConnectionVerifier.run(configuration: config, authorized: true, pcm: sample, transport: transport, deadline: .seconds(12), progress: { _ in })
        #expect(report.readiness == .noAPIEngineeringReady)
        #expect(!report.live && !report.canEnableCloud)
        #expect(report.pipelineCompleted)
        #expect(report.services.count == 3 && report.services.allSatisfy { $0.state == .verified })
        #expect(report.reviewRequests <= ConnectionCheckLimits.maximumReviewRequests)
        let state = try await peer.snapshot(), requests = try #require(state["gpt_requests"] as? [[String: Any]])
        #expect(requests.count <= 6)
        if fault == "each_reconnect" { #expect(requests.count == 4) }
        if fault == "unsupported" { #expect(state["unsupported_upgrades"] as? Int == 1) }
        #expect(requests.allSatisfy { $0["max_output_tokens"] as? Int == 4096 })
        let connections = try #require(state["connections"] as? [[String: Any]])
        let asr = connections.filter { ["qwen", "assembly"].contains($0["provider"] as? String ?? "") }
        let hash = SHA256.hash(data: sample).map { String(format: "%02x", $0) }.joined()
        #expect(asr.count == 2 && asr.allSatisfy { $0["pcm_bytes"] as? Int == sample.count && $0["sha256"] as? String == hash && $0["eos"] as? Bool == true })
        #expect((state["violations"] as? [String])?.isEmpty == true)
        print("PROTOCOL_WIZARD case=\(peer.id) scenario=\(fault) pipeline_completed=\(report.pipelineCompleted) wire_gpt_requests=\(requests.count) readiness=\(report.readiness.rawValue)")
    }

    @Test(arguments: ["normal", "unbacked_selection"])
    func productionSessionPublishesOneChangingTextAndFinalizesAfterBothExpertsEOS(fault: String) async throws {
        let peer = try ProtocolPeer(), config = configuration()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-wire-engine-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root), record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk(); try journal.append(pcm); try journal.closeChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: Int64(pcm.count / 2))
        let ticket = try await store.beginFusionRecognition(recordingID: record.id)
        var dependencies = RecognitionPipelineDependencies.live
        dependencies.credential = { _ in simulatorCredential }
        dependencies.streaming = { provider in
            if provider == .qwenMessage { return try QwenMessageProvider(testEndpoint: peer.url("qwen"), timeout: 2) }
            if provider == .assemblyAI { return try AssemblyStreamingProvider(testEndpoint: peer.url("assembly"), timeout: 2) }
            throw ProviderFailure.configuration("unexpected provider in protocol fixture")
        }
        dependencies.makeReviewClient = { peer.reviewClient(fault: fault) }
        let session = MultiRecognitionSession(store: store, ticket: ticket, configuration: config, dependencies: dependencies, finalizationTimeout: .seconds(5))
        var displayed = [String]()
        for index in stride(from: 0, to: pcm.count, by: 3200) {
            session.append(pcm.subdata(in: index..<min(index + 3200, pcm.count)))
            try await Task.sleep(for: .milliseconds(90))
            // Do not feed the correcting audio until the earlier hypothesis is
            // observable in the real Store. A fixed 90 ms poll can miss a valid
            // short-lived partial when the full CI suite is scheduling other work.
            if index == 0 || index == 6400 {
                let expected = index == 0 ? "请支付" : "不要"
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                var observed = false
                repeat {
                    let text = try await store.recording(id: record.id)?.text ?? ""
                    if !text.isEmpty && displayed.last != text { displayed.append(text) }
                    if text.contains(expected) { observed = true; break }
                    try await Task.sleep(for: .milliseconds(20))
                } while ContinuousClock.now < deadline
                #expect(observed, "Expected live hypothesis must be visible before feeding its correction: \(expected)")
            }
            let text = try await store.recording(id: record.id)?.text ?? ""
            if !text.isEmpty && displayed.last != text { displayed.append(text) }
        }
        #expect(!displayed.isEmpty, "Real ASR network partials must reach the production publication path before EOS")
        #expect(displayed.contains { $0.contains("请支付") })
        #expect(displayed.contains { $0.contains("不要") })
        try await store.finishRecording(id: record.id); session.finish(); await session.wait()
        let final = try #require(try await store.recording(id: record.id))
        #expect(final.recognitionState == (fault == "normal" ? .completed : .failed))
        #expect(final.text == "请不要支付15元，send the report。")
        if fault == "normal" { #expect(try await store.latestDispatchableRevision(recordingID: record.id)?.text == final.text) }
        else { #expect(try await store.latestDispatchableRevision(recordingID: record.id) == nil) }
        #expect(try await store.modelRuns(recordingID: record.id).allSatisfy { $0.state != .running })
        #expect(try Data(contentsOf: store.audioDirectory.appendingPathComponent(journal.relativePath)).dropFirst(44) == pcm)
        let state = try await peer.snapshot()
        let requests = try #require(state["gpt_requests"] as? [[String: Any]])
        #expect(requests.count >= 2, "Live review plus forced EOS review must use the real GPT transport")
        #expect((state["violations"] as? [String])?.isEmpty == true)
        print("PROTOCOL_ENGINE case=\(peer.id) visible_revisions=\(displayed.count) gpt_requests=\(requests.count) final_state=\(final.recognitionState.rawValue) scope=SIMULATED_PROTOCOL_NOT_LIVE_CLOUD")
        try await store.close()
    }
}
