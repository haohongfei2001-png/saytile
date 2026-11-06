import Foundation
import Testing
@testable import SaytileKit

@Suite("Chinese and multilingual provider wire contracts")
struct ChineseProviderProtocolTests {
    private let taskID = "fixture-task"
    private var qwen: ModelConfiguration {
        .init(purpose: .chineseASR, provider: .qwenMessage,
              model: "qwen-audio-3.1-asr-flash-message", region: "cn-beijing", workspaceID: "fixture-workspace")
    }
    private func envelope(_ event: String, sentence: [String: Any]? = nil) -> [String: Any] {
        var value: [String: Any] = ["header": ["event": event, "task_id": taskID]]
        if let sentence { value["payload"] = ["output": ["sentence": sentence]] }
        return value
    }
    private func sentence(_ id: Int, _ text: String, _ final: Bool,
                          start: Double = 100, end: Double = 1000) -> [String: Any] {
        ["sentence_id": id, "text": text, "sentence_end": final, "begin_time": start, "end_time": end]
    }
    private func token(_ text: String, _ final: Bool, start: Double = 100, end: Double = 200,
                       language: String = "zh") -> [String: Any] {
        ["text": text, "is_final": final, "start_ms": start, "end_ms": end,
         "language": language, "confidence": 0.91]
    }
    private func json(_ string: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any])
    }

    @Test func qwenRequestUsesRegionalWorkspaceAndExplicitPartials() throws {
        let request = try QwenMessageCodec.request(configuration: qwen, credential: "fixture-secret")
        #expect(request.url?.absoluteString == "wss://fixture-workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-secret")
        let start = try json(QwenMessageCodec.startMessage(configuration: qwen, taskID: taskID))
        let payload = try #require(start["payload"] as? [String: Any])
        let parameters = try #require(payload["parameters"] as? [String: Any])
        #expect(parameters["intermediate_result_enabled"] as? Bool == true)
        #expect(parameters["disfluency_removal_enabled"] as? Bool == false)
        #expect(parameters["sample_rate"] as? Int == 16_000)
        #expect(parameters["language_hints"] as? [String] == ["zh", "en"])
        #expect(!String(describing: start).contains("fixture-secret"))
        let finish = try json(QwenMessageCodec.finishMessage(taskID: taskID))
        let header = try #require(finish["header"] as? [String: Any])
        #expect(header["action"] as? String == "finish-task")
        #expect(header["task_id"] as? String == taskID)
    }

    @Test func qwenRevisionReplacesSentenceAndPreservesUTF16Evidence() throws {
        var codec = QwenMessageCodec(taskID: taskID)
        let started = try codec.consume(envelope("task-started"))
        #expect(started == nil)
        let firstValue = try codec.consume(envelope("result-generated", sentence: sentence(1, "我想用水", false)))
        let first = try #require(firstValue)
        #expect(first.stableUTF16Length == 0)
        let settledValue = try codec.consume(envelope("result-generated", sentence: sentence(1, "我想用 SwiftUI😀。", true)))
        let settled = try #require(settledValue)
        #expect(settled.text == "我想用 SwiftUI😀。")
        #expect(settled.stableUTF16Length == settled.text.utf16.count)
        #expect(settled.timingGranularity == "segment")
        #expect(settled.tokens.count == 1)
        #expect(settled.tokens.first?.startSeconds == 0.1)
        #expect(settled.tokens.first?.endSeconds == 1)
        #expect(settled.tokens.map(\.text).joined() == settled.text)
        let secondValue = try codec.consume(envelope("result-generated", sentence: sentence(2, " 再查询 SQLite。", false, start: 1100, end: 2000)))
        let second = try #require(secondValue)
        #expect(second.text == "我想用 SwiftUI😀。 再查询 SQLite。")
        #expect(second.stableUTF16Length == settled.text.utf16.count)
        #expect(second.tokens.map(\.text).joined() == second.text)
        _ = try codec.consume(envelope("result-generated", sentence: sentence(2, " 再查询 SQLite。", true, start: 1100, end: 2000)))
        let doneValue = try codec.consume(envelope("task-finished"))
        let done = try #require(doneValue)
        #expect(done.isComplete)
        #expect(done.stableUTF16Length == done.text.utf16.count)
        #expect(done.tokens.allSatisfy { $0.rawConfidence == nil && $0.language == nil })
    }

    @Test func qwenStashAndHeartbeatAreNotDuplicateSentences() throws {
        var codec = QwenMessageCodec(taskID: taskID)
        _ = try codec.consume(envelope("task-started"))
        var current = sentence(1, "不是十五。", true)
        current["stash"] = ["sentence_id": 2, "text": "是五十", "begin_time": 1100, "current_time": 1800]
        let eventValue = try codec.consume(envelope("result-generated", sentence: current))
        let event = try #require(eventValue)
        #expect(event.text == "不是十五。是五十")
        #expect(event.tokens.last?.endSeconds == 1.8)
        #expect(event.stableUTF16Length == "不是十五。".utf16.count)
        let heartbeat = try codec.consume(envelope("result-generated", sentence: ["heartbeat": true]))
        #expect(heartbeat == nil)
        let revisedValue = try codec.consume(envelope("result-generated", sentence: sentence(2, "是五十，不是十五。", true, start: 1100, end: 2300)))
        let revised = try #require(revisedValue)
        #expect(revised.text == "不是十五。是五十，不是十五。")
        #expect(revised.tokens.map(\.text).joined() == revised.text)
    }

    @Test func qwenCumulativeWindowStartsAtZeroAfterLeadingSilence() throws {
        var codec = QwenMessageCodec(taskID: taskID)
        _ = try codec.consume(envelope("task-started"))
        let partialValue = try codec.consume(envelope("result-generated", sentence:
            sentence(1, "不要", false, start: 1450, end: 1750)))
        let partial = try #require(partialValue)
        #expect(partial.audioStartSeconds == 0)
        #expect(partial.tokens.first?.startSeconds == 1.45)
        #expect(partial.tokens.first?.endSeconds == 1.75)
        _ = try codec.consume(envelope("result-generated", sentence:
            sentence(1, "不要删。", true, start: 1450, end: 2100)))
        let completeValue = try codec.consume(envelope("task-finished"))
        let complete = try #require(completeValue)
        #expect(complete.audioStartSeconds == 0)
        #expect(complete.audioEndSeconds == 2.1)
        #expect(complete.tokens.first?.startSeconds == 1.45)
        #expect(complete.tokens.map(\.text).joined() == complete.text)
    }

    @Test func qwenMissingPartialTimeDoesNotFabricateWordAlignment() throws {
        var codec = QwenMessageCodec(taskID: taskID)
        _ = try codec.consume(envelope("task-started"))
        let valueValue = try codec.consume(envelope("result-generated", sentence:
            ["sentence_id": 1, "text": "ChatGPT", "sentence_end": false, "begin_time": 100, "end_time": NSNull()]))
        let value = try #require(valueValue)
        #expect(value.text == "ChatGPT")
        #expect(value.tokens.isEmpty)
        #expect(value.timingGranularity == "utterance")
        #expect(throws: Error.self) { try codec.consume(envelope("task-finished")) }
    }

    @Test func qwenRejectsWrongGenerationAndIncompleteFinal() throws {
        var codec = QwenMessageCodec(taskID: taskID)
        #expect(throws: Error.self) { try codec.consume(["header": ["event": "task-started", "task_id": "stale-task"]]) }
        _ = try codec.consume(envelope("task-started"))
        #expect(throws: Error.self) { try codec.consume(envelope("result-generated", sentence:
            ["sentence_id": 1, "text": "不要", "sentence_end": true])) }
        var config = qwen
        config.context = String(repeating: "术", count: 401)
        #expect(throws: Error.self) { try QwenMessageCodec.startMessage(configuration: config, taskID: taskID) }
        config = qwen
        config.workspaceID = "wrong/path"
        #expect(throws: Error.self) { try QwenMessageCodec.request(configuration: config, credential: "fixture") }
    }

    @Test func sonioxUsesHeaderAuthRawPCMAndNonrestrictiveLanguageHints() throws {
        let config = ModelConfiguration(purpose: .multilingualASR, provider: .soniox, model: "stt-rt-v6")
        let request = try SonioxStreamingCodec.request(configuration: config, credential: "fixture-secret")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-secret")
        let start = try json(SonioxStreamingCodec.startMessage(configuration: config, referenceID: taskID))
        #expect(start["api_key"] == nil)
        #expect(start["audio_format"] as? String == "pcm_s16le")
        #expect(start["num_channels"] as? Int == 1)
        #expect(start["language_hints_strict"] as? Bool == false)
        #expect(start["enable_language_identification"] as? Bool == true)
        #expect(start["translation"] == nil)
    }

    @Test func sonioxAppendsFinalsButReplacesNonfinalTail() throws {
        var codec = SonioxStreamingCodec(referenceID: taskID)
        let firstValue = try codec.consume(["tokens": [token("我用 ", true), token("swift", false, language: "en")]])
        let first = try #require(firstValue)
        #expect(first.text == "我用 swift")
        #expect(first.stableUTF16Length == "我用 ".utf16.count)
        let nextValue = try codec.consume(["tokens": [token("SwiftUI😀", false, start: 220, end: 700, language: "en")]])
        let next = try #require(nextValue)
        #expect(next.text == "我用 SwiftUI😀")
        #expect(next.language == "mixed")
        #expect(next.tokens.map(\.text).joined() == next.text)
        let finalValue = try codec.consume(["tokens": [token("SwiftUI😀", true, start: 220, end: 700, language: "en"),
                                                                            ["text": "<end>", "is_final": true]],
                                                "total_audio_proc_ms": 800])
        let final = try #require(finalValue)
        #expect(final.text == "我用 SwiftUI😀")
        #expect(final.stableUTF16Length == final.text.utf16.count)
        #expect(final.timingGranularity == "token")
        #expect(final.tokens.last?.rawConfidence == 0.91)
        #expect(final.audioEndSeconds == 0.8)
        let doneValue = try codec.consume(["tokens": [], "finished": true])
        let done = try #require(doneValue)
        #expect(done.isComplete)
        #expect(done.text == final.text)
    }

    @Test func sonioxControlTokensAndMissingTimeCannotBecomeSpokenEvidence() throws {
        var codec = SonioxStreamingCodec(referenceID: taskID)
        let resultValue = try codec.consume(["tokens": [token("停。", true), ["text": "<fin>"], ["text": "<end>"]]])
        let result = try #require(resultValue)
        #expect(result.text == "停。")
        let noTimeValue = try codec.consume(["tokens": [["text": " 好", "is_final": false]], "total_audio_proc_ms": 1200])
        let noTime = try #require(noTimeValue)
        #expect(noTime.text == "停。 好")
        #expect(noTime.tokens.isEmpty)
        #expect(noTime.timingGranularity == "utterance")
        #expect(noTime.audioEndSeconds == 1.2)
        #expect(throws: Error.self) { try codec.consume(["tokens": [], "finished": true]) }
    }

    @Test func sonioxCumulativeWindowStartsAtZeroAfterLeadingSilence() throws {
        var codec = SonioxStreamingCodec(referenceID: taskID)
        let partialValue = try codec.consume(["tokens": [token("我用", false, start: 1450, end: 1750)]])
        let partial = try #require(partialValue)
        #expect(partial.audioStartSeconds == 0)
        #expect(partial.tokens.first?.startSeconds == 1.45)
        #expect(partial.tokens.first?.endSeconds == 1.75)
        _ = try codec.consume(["tokens": [token("我用 ", true, start: 1450, end: 1750),
                                         token("SwiftUI", true, start: 1900, end: 2400, language: "en")]])
        let completeValue = try codec.consume(["tokens": [], "finished": true, "total_audio_proc_ms": 2800])
        let complete = try #require(completeValue)
        #expect(complete.audioStartSeconds == 0)
        #expect(complete.audioEndSeconds == 2.8)
        #expect(complete.tokens.first?.startSeconds == 1.45)
        #expect(complete.tokens.last?.startSeconds == 1.9)
        #expect(complete.tokens.map(\.text).joined() == complete.text)
    }

    @Test func providerErrorsAreRedactedAndUntranslated() throws {
        var qwenCodec = QwenMessageCodec(taskID: taskID)
        do {
            _ = try qwenCodec.consume(["header": ["event": "task-failed", "task_id": taskID,
                                                "error_code": "InvalidApiKey", "error_message": "secret-leak"]])
            Issue.record("Expected auth failure")
        } catch {
            #expect(!error.localizedDescription.contains("secret-leak"))
            #expect((error as? ProviderFailure)?.canRetryAutomatically == false)
        }
        var sonioxCodec = SonioxStreamingCodec(referenceID: taskID)
        #expect(throws: Error.self) { try sonioxCodec.consume(["error_code": 401, "error_message": "secret-leak"]) }
        #expect(throws: Error.self) { try sonioxCodec.consume(["tokens": [["text": "translation", "is_final": true, "translation_status": "translation"]]]) }
    }
}
