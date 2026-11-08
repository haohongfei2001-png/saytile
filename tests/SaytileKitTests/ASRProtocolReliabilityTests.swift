import Foundation
import Testing
@testable import SaytileKit

@Suite("ASR protocol lifecycle and sanitized diagnosis")
struct ASRProtocolReliabilityTests {
    private func qwenEvent(_ type: String, sentence: [String: Any]? = nil) -> [String: Any] {
        var result: [String: Any] = ["header": ["task_id": "fixture", "event": type]]
        if let sentence { result["payload"] = ["output": ["sentence": sentence]] }
        return result
    }
    private func qwenSentence(_ text: String, final: Bool) -> [String: Any] {
        ["sentence_id": 1, "text": text, "sentence_end": final, "begin_time": 0, "end_time": 500]
    }
    private func assemblyTurn(_ text: String, final: Bool) -> [String: Any] {
        ["turn_order": 0, "transcript": text, "end_of_turn": final, "turn_is_formatted": final]
    }

    @Test(arguments: [
        (1008, "Unauthorized Connection: Invalid API key", "authorization_failed"),
        (1008, "Unauthorized Connection: Insufficient funds", "quota_exhausted"),
        (1008, "Unauthorized Connection: Too many concurrent sessions", "rate_limited"),
        (1008, "Unauthorized Connection: API key is disabled", "permission_denied"),
        (1008, "Unauthorized Connection: No metronome account found", "quota_exhausted"),
        (3005, "Session Cancelled: An error occurred", "connection_failed"),
        (3008, "Session Expired: Maximum session duration exceeded", "connection_failed"),
        (3007, "Input duration violation: 10 ms. Expected between 20 and 1000 ms", "protocol_incompatible")
    ])
    func assemblyServiceFailuresAreActionableWithoutRawErrorOutput(code: Int, message: String, expected: String) {
        let failure = AssemblyStreamingProvider.serviceFailure(["type": "Error", "error_code": code, "error": message])
        #expect(failure.diagnosticCode == expected)
        #expect(!failure.localizedDescription.contains(message))
        if expected == "rate_limited" {
            #expect(failure.canRetryAutomatically)
            #expect(failure.minimumRetryDelay >= 60)
        } else if ["authorization_failed", "permission_denied", "quota_exhausted", "protocol_incompatible"].contains(expected) {
            #expect(!failure.canRetryAutomatically)
        }
    }

    @Test(arguments: [("InvalidApiKey", "authorization_failed"), ("AccessDenied", "permission_denied"),
                      ("InvalidWorkspace", "region_workspace_mismatch"), ("Throttling", "rate_limited"),
                      ("Arrearage", "quota_exhausted"), ("InvalidParameter", "invalid_configuration")])
    func qwenTaskFailuresRetainSafeCategories(code: String, expected: String) {
        var codec = QwenMessageCodec(taskID: "fixture")
        do {
            _ = try codec.consume(["header": ["task_id": "fixture", "event": "task-failed", "error_code": code,
                                              "error_message": "SECRET_SENTINEL_正在识别的私人文本"]])
            Issue.record("Expected a task failure")
        } catch {
            #expect((error as? ProviderFailure)?.diagnosticCode == expected)
            #expect(!error.localizedDescription.contains("SECRET_SENTINEL"))
            #expect(!error.localizedDescription.contains("私人文本"))
        }
    }

    @Test func assemblyFinalCannotRegressToLatePartialOrConflictingFinal() throws {
        var codec = AssemblyTranscriptAccumulator(requestID: "fixture")
        let approved = try codec.accept(assemblyTurn("Do not pay 15 😀", final: true), duration: 1)
        let late = try codec.accept(assemblyTurn("Pay 50", final: false), duration: 1)
        #expect(late == approved)
        #expect(codec.allTurnsFinal)
        #expect(try codec.accept(assemblyTurn("Do not pay 15 😀", final: true), duration: 1) == approved)
        #expect(throws: ProviderFailure.self) { try codec.accept(assemblyTurn("Pay 50", final: true), duration: 1) }
        #expect(codec.event(duration: 1) == approved)
    }

    @Test func qwenFinalCannotRegressToLatePartialOrConflictingFinal() throws {
        var codec = QwenMessageCodec(taskID: "fixture")
        _ = try codec.consume(qwenEvent("task-started"))
        let approved = try codec.consume(qwenEvent("result-generated", sentence: qwenSentence("不要付15元😀", final: true)))
        let late = try codec.consume(qwenEvent("result-generated", sentence: qwenSentence("支付50元", final: false)))
        #expect(late == approved)
        #expect(throws: ProviderFailure.self) {
            try codec.consume(qwenEvent("result-generated", sentence: qwenSentence("支付50元", final: true)))
        }
        let done = try #require(try codec.consume(qwenEvent("task-finished")))
        #expect(done.text == approved?.text)
        #expect(done.isComplete)
    }

    @Test func invalidJSONAlwaysHasSafeProtocolDiagnosis() {
        do {
            _ = try ProviderJSON.object(.string("{SECRET_SENTINEL invalid"))
            Issue.record("Expected invalid JSON rejection")
        } catch {
            #expect((error as? ProviderFailure)?.diagnosticCode == "protocol_incompatible")
            #expect(!error.localizedDescription.contains("SECRET_SENTINEL"))
        }
    }

    @Test func qwenConsentMustBePresentAtTheProductionNetworkBoundary() throws {
        var configuration = ModelConfiguration(purpose: .chineseASR, provider: .qwenMessage,
            model: "qwen-audio-3.1-asr-flash-message", region: "cn-beijing", workspaceID: "fixture-workspace")
        #expect(throws: ProviderFailure.self) {
            try QwenMessageCodec.request(configuration: configuration, credential: "simulator-fixture-credential")
        }
        configuration.cloudConsent = true
        #expect(try QwenMessageCodec.request(configuration: configuration, credential: "simulator-fixture-credential").url?.host ==
                "fixture-workspace.cn-beijing.maas.aliyuncs.com")
    }

    @Test func beginCannotConfirmAnUnidentifiedAssemblySession() {
        let configuration = ModelConfiguration(purpose: .englishASR, provider: .assemblyAI,
            model: "universal-3-6-pro", cloudConsent: true)
        for identifier: Any in [NSNull(), ""] {
            #expect(throws: ProviderFailure.self) {
                try AssemblyStreamingProvider.verifyBegin(["type": "Begin", "id": identifier,
                    "configuration": ["model": "universal-3-6-pro", "mode": "max_accuracy"]], configuration: configuration)
            }
        }
    }

    @Test func qwenMissingSentenceCannotClaimStableOrCompletedText() throws {
        var codec = QwenMessageCodec(taskID: "fixture")
        _ = try codec.consume(qwenEvent("task-started"))
        var second = qwenSentence("支付15元。", final: true)
        second["sentence_id"] = 2
        let gap = try #require(try codec.consume(qwenEvent("result-generated", sentence: second)))
        #expect(gap.stableUTF16Length == 0)
        #expect(throws: ProviderFailure.self) { try codec.consume(qwenEvent("task-finished")) }
        let repaired = try #require(try codec.consume(qwenEvent("result-generated", sentence: qwenSentence("不要", final: true))))
        #expect(repaired.text == "不要支付15元。")
        #expect(repaired.stableUTF16Length == repaired.text.utf16.count)
        #expect(try codec.consume(qwenEvent("task-finished"))?.isComplete == true)
    }

    @Test func qwenZeroIdentifierIsOnlyValidForAHeartbeat() throws {
        var codec = QwenMessageCodec(taskID: "fixture")
        _ = try codec.consume(qwenEvent("task-started"))
        var sentence = qwenSentence("不要支付15元。", final: true)
        sentence["sentence_id"] = 0
        #expect(throws: ProviderFailure.self) { try codec.consume(qwenEvent("result-generated", sentence: sentence)) }
        sentence["heartbeat"] = true
        #expect(try codec.consume(qwenEvent("result-generated", sentence: sentence)) == nil)
    }

    @Test func loopbackEndpointCannotExportCredentialsOrOverrideOfficialModelQuery() throws {
        let good = try #require(URL(string: "ws://127.0.0.1:12345/assembly?scenario=quota"))
        #expect(try ProviderTestEndpoint.validate(good, schemes: ["ws"]) == good)
        for bad in ["ws://example.com:12345/assembly", "ws://localhost:12345/assembly", "ws://127.0.0.1/assembly",
                    "ws://secret@127.0.0.1:12345/assembly", "ws://127.0.0.1:12345/assembly#secret", "https://127.0.0.1:12345/assembly"] {
            #expect(throws: ProviderFailure.self) { try ProviderTestEndpoint.validate(URL(string: bad)!, schemes: ["ws"]) }
        }
        let configuration = ModelConfiguration(purpose: .englishASR, provider: .assemblyAI, model: "universal-3-6-pro", cloudConsent: true)
        let request = try AssemblyStreamingProvider.request(configuration: configuration, credential: "simulator-fixture-credential")
        let routed = try ProviderTestEndpoint.applying(good, to: request)
        #expect(routed.value(forHTTPHeaderField: "Authorization") == "simulator-fixture-credential")
        #expect(routed.url?.absoluteString.contains("speech_model=universal-3-6-pro") == true)
        #expect(routed.url?.absoluteString.contains("scenario=quota") == true)
        #expect(throws: ProviderFailure.self) {
            try ProviderTestEndpoint.applying(URL(string: "ws://127.0.0.1:12345/assembly?speech_model=other")!, to: request)
        }
    }
}
