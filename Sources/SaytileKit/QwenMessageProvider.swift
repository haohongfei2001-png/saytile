import Foundation
import CoreFoundation

/// Qwen Message is an actual duplex PCM service. Intermediate results are explicitly
/// enabled: the model's default message-oriented response is not a live-text contract.
public struct QwenMessageProvider: StreamingASRProvider {
    private let testEndpoint: URL?
    private let timeoutOverride: TimeInterval?
    private let onReady: @Sendable () -> Void
    public init(onReady: @escaping @Sendable () -> Void = {}) {
        testEndpoint = nil; timeoutOverride = nil; self.onReady = onReady
    }
    init(testEndpoint: URL, timeout: TimeInterval = 1, onReady: @escaping @Sendable () -> Void = {}) throws {
        self.testEndpoint = try ProviderTestEndpoint.validate(testEndpoint, schemes: ["ws", "wss"])
        guard timeout.isFinite, timeout > 0 else { throw ProviderFailure.configuration("协议测试超时须为正数。") }
        timeoutOverride = timeout; self.onReady = onReady
    }

    public func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
                    emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        let taskID = UUID().uuidString
        var request = try QwenMessageCodec.request(configuration: configuration, credential: credential)
        if let testEndpoint { request = try ProviderTestEndpoint.applying(testEndpoint, to: request) }
        let start = try QwenMessageCodec.startMessage(configuration: configuration, taskID: taskID)
        let finish = try QwenMessageCodec.finishMessage(taskID: taskID)
        let session = ChineseASRWebSocket.makeSession()
        let socket = session.webSocketTask(with: request)
        defer { socket.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
        do { try await withTaskCancellationHandler {
            socket.resume()
            try await ChineseASRWebSocket.send(.string(start), to: socket, timeout: timeoutOverride ?? 20)
            var codec = QwenMessageCodec(taskID: taskID)
            let first = try await ChineseASRWebSocket.receive(from: socket, timeout: timeoutOverride ?? 20)
            _ = try codec.consume(ProviderJSON.object(first))
            guard codec.hasStarted else { throw ProviderFailure.protocolViolation("qwen_ready") }
            try Task.checkCancellation()
            onReady()
            try await ChineseASRWebSocket.stream(audio: audio, socket: socket, endMessage: finish,
                                                decoder: codec, writeTimeout: timeoutOverride ?? 20, drainTimeout: timeoutOverride ?? 45, emit: emit)
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
        } catch { throw EnglishProviderSupport.failure(error, socket: socket) }
    }
}

struct QwenMessageCodec: ChineseASRFrameDecoder {
    struct Segment: Sendable {
        var text: String
        var start: Double?
        var end: Double?
        var isFinal: Bool
        var words: [ProviderToken]?
    }
    let taskID: String
    private(set) var hasStarted = false
    private(set) var isComplete = false
    private var segments: [Int: Segment] = [:]
    init(taskID: String) { self.taskID = taskID }

    static func request(configuration: ModelConfiguration, credential: String) throws -> URLRequest {
        try configuration.validate()
        guard configuration.provider == .qwenMessage,
              configuration.model == "qwen-audio-3.1-asr-flash-message" else {
            throw ProviderFailure.configuration("此适配器支持 qwen-audio-3.1-asr-flash-message；其他 Qwen 协议需要独立适配器。")
        }
        guard configuration.cloudConsent else {
            throw ProviderFailure.configuration("请先授权 Qwen 处理音频。")
        }
        try ChineseASRWebSocket.validateCredential(credential)
        guard let url = URL(string: "wss://\(configuration.workspaceID).\(configuration.region).maas.aliyuncs.com/api-ws/v1/inference") else {
            throw ProviderFailure.configuration("Qwen 工作空间或地域配置无效。")
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func startMessage(configuration: ModelConfiguration, taskID: String) throws -> String {
        var input: [String: Any] = [:]
        if !configuration.context.isEmpty {
            // The documented Message context limit is 400 characters per turn.
            // Reject rather than silently discard the user's requested terminology.
            guard configuration.context.count <= 400 else {
                throw ProviderFailure.configuration("Qwen Message 的单轮上下文最多 400 字，请缩短此模型的话题上下文。")
            }
            input["context"] = [["role": "user", "content": [["type": "input_text", "text": configuration.context]]]]
        }
        return try ProviderJSON.string([
            "header": ["action": "run-task", "task_id": taskID, "streaming": "duplex"],
            "payload": ["task_group": "audio", "task": "asr", "function": "recognition",
                        "model": configuration.model, "input": input,
                        "parameters": ["format": "pcm", "sample_rate": 16_000,
                                       "intermediate_result_enabled": true,
                                       "disfluency_removal_enabled": false,
                                       "keep_dialect": true, "language_hints": ["zh", "en"]]]
        ])
    }

    static func finishMessage(taskID: String) throws -> String {
        try ProviderJSON.string(["header": ["action": "finish-task", "task_id": taskID, "streaming": "duplex"],
                                 "payload": ["input": [String: String]()]])
    }

    mutating func consume(_ object: [String: Any]) throws -> ProviderTranscriptEvent? {
        guard !isComplete,
              let header = object["header"] as? [String: Any],
              header["task_id"] as? String == taskID,
              let event = header["event"] as? String else {
            throw ProviderFailure.protocolViolation("qwen_envelope")
        }
        if event == "task-failed" {
            let code = (header["error_code"] as? String ?? "").lowercased()
            if code.contains("workspace") || code.contains("region") { throw ProviderFailure.regionMismatch }
            if code.contains("auth") || code.contains("apikey") {
                throw ProviderFailure.authorization
            }
            if code.contains("accessdenied") || code.contains("forbidden") || code.contains("permission") {
                throw ProviderFailure.permission
            }
            if code.contains("throttl") || code.contains("ratelimit") || code.contains("rate_limit") {
                throw ProviderFailure.rateLimited
            }
            if code.contains("quota") || code.contains("balance") || code.contains("arrear") {
                throw ProviderFailure.quota
            }
            if code.contains("invalidparameter") || code.contains("modelnotfound") || code.contains("unsupported") {
                throw ProviderFailure.configuration("Qwen 模型或请求参数不受支持；请检查模型配置。")
            }
            // Do not surface error_message, which may contain credentials or user audio text.
            throw ProviderFailure.connection
        }
        switch event {
        case "task-started":
            guard !hasStarted else { throw ProviderFailure.protocolViolation("qwen_duplicate_start") }
            hasStarted = true
            return nil
        case "result-generated":
            guard hasStarted,
                  let payload = object["payload"] as? [String: Any],
                  let output = payload["output"] as? [String: Any],
                  let sentence = output["sentence"] as? [String: Any] else {
                throw ProviderFailure.protocolViolation("qwen_sentence")
            }
            if sentence["heartbeat"] as? Bool == true { return nil }
            let id = try update(sentence, finalKey: "sentence_end")
            if let stash = sentence["stash"] as? [String: Any],
               let nextID = stash["sentence_id"] as? Int, nextID > id,
               segments[nextID]?.isFinal != true {
                _ = try update(stash, finalKey: nil)
            }
            return snapshot()
        case "task-finished":
            guard hasStarted, segments.values.allSatisfy({ $0.text.isEmpty || $0.isFinal }),
                  segments.keys.sorted() == Array(1..<(segments.count + 1)) else {
                throw ProviderFailure.incomplete
            }
            isComplete = true
            return snapshot()
        default:
            throw ProviderFailure.protocolViolation("qwen_event")
        }
    }

    private mutating func update(_ sentence: [String: Any], finalKey: String?) throws -> Int {
        guard let id = sentence["sentence_id"] as? Int, id > 0, id < 100_000,
              let text = sentence["text"] as? String, text.utf16.count <= 1_000_000 else {
            throw ProviderFailure.protocolViolation("qwen_segment")
        }
        let final = finalKey.flatMap { sentence[$0] as? Bool } ?? false
        if let prior = segments[id], prior.isFinal {
            guard !final || prior.text == text else { throw ProviderFailure.protocolViolation("qwen_conflicting_final") }
            return id
        }
        let start = ChineseASRWebSocket.seconds(sentence["begin_time"])
        var end = ChineseASRWebSocket.seconds(sentence["end_time"])
            ?? ChineseASRWebSocket.seconds(sentence["current_time"])
        if end == nil, let words = sentence["words"] as? [[String: Any]] {
            end = words.compactMap { ChineseASRWebSocket.seconds($0["end_time"]) }.max()
        }
        if let start, let end, end < start { throw ProviderFailure.protocolViolation("qwen_timing") }
        if final && !text.isEmpty && (start == nil || end == nil) {
            throw ProviderFailure.protocolViolation("qwen_final_timing")
        }
        // Every update replaces the same sentence; partial revisions are never appended.
        segments[id] = Segment(text: text, start: start, end: end, isFinal: final,
                               words: Self.alignedWords(sentence["words"], text: text,
                                                        start: start, end: end, isFinal: final))
        return id
    }

    /// Preserve only provider-supplied word times. Spaces omitted by the word objects
    /// stay attached to the following literal word, without acquiring invented times.
    /// Any omitted spoken text, invalid timestamp or punctuation mismatch falls back
    /// to the true sentence interval instead of manufacturing a finer alignment.
    private static func alignedWords(_ raw: Any?, text: String, start: Double?, end: Double?,
                                     isFinal: Bool) -> [ProviderToken]? {
        guard let words = raw as? [[String: Any]], !words.isEmpty else { return nil }
        let source = text as NSString
        var cursor = 0, previousStart: Double = -1
        var result: [ProviderToken] = []
        for word in words {
            guard let literal = word["text"] as? String, !literal.isEmpty,
                  let wordStart = ChineseASRWebSocket.seconds(word["begin_time"]),
                  let wordEnd = ChineseASRWebSocket.seconds(word["end_time"]),
                  wordEnd >= wordStart, wordStart >= previousStart,
                  start.map({ wordStart >= $0 }) ?? true,
                  end.map({ wordEnd <= $0 }) ?? true else { return nil }
            let punctuation: String
            if let value = word["punctuation"] {
                guard let value = value as? String else { return nil }
                punctuation = value
            } else { punctuation = "" }
            let value = literal + punctuation
            let range = source.range(of: value, options: .literal,
                                     range: NSRange(location: cursor, length: source.length - cursor))
            guard range.location != NSNotFound else { return nil }
            let gap = source.substring(with: NSRange(location: cursor, length: range.location - cursor))
            guard gap.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
            let boundary = NSMaxRange(range)
            let exactText = source.substring(with: NSRange(location: cursor, length: boundary - cursor))
            result.append(.init(text: exactText, startSeconds: wordStart, endSeconds: wordEnd, isFinal: isFinal))
            cursor = boundary
            previousStart = wordStart
        }
        let trailing = source.substring(from: cursor)
        guard trailing.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
        if !trailing.isEmpty { result[result.count - 1].text += trailing }
        guard Array(result.map(\.text).joined().utf16) == Array(text.utf16) else { return nil }
        return result
    }

    private func snapshot() -> ProviderTranscriptEvent {
        let ordered = segments.sorted { $0.key < $1.key }
        var text = "", stable = 0, stableOpen = true, expectedID = 1
        var tokens: [ProviderToken] = [], fullyTimed = true, hasSentenceTokens = false
        for (id, segment) in ordered {
            if id != expectedID { stableOpen = false }
            expectedID = id + 1
            text += segment.text
            if !segment.isFinal { stableOpen = false }
            if stableOpen { stable += segment.text.utf16.count }
            guard !segment.text.isEmpty else { continue }
            if let words = segment.words {
                tokens.append(contentsOf: words)
            } else if let start = segment.start, let end = segment.end {
                hasSentenceTokens = true
                tokens.append(.init(text: segment.text, startSeconds: start, endSeconds: end,
                                    isFinal: segment.isFinal))
            } else { fullyTimed = false }
        }
        // Mixed word/sentence evidence is conservatively labelled segment while still
        // retaining every genuine word boundary. No text-length-based interpolation.
        // This is the cumulative recording window, including leading silence. Speech
        // onset belongs in the segment tokens, not in the candidate window's origin.
        return .init(text: text, stableUTF16Length: stable,
                     audioStartSeconds: 0,
                     audioEndSeconds: ordered.compactMap { $0.value.end }.max() ?? 0,
                     timingGranularity: fullyTimed ? (hasSentenceTokens || tokens.isEmpty ? "segment" : "word") : "utterance",
                     isComplete: isComplete, requestID: taskID, tokens: fullyTimed ? tokens : [])
    }
}

protocol ChineseASRFrameDecoder: Sendable {
    mutating func consume(_ object: [String: Any]) throws -> ProviderTranscriptEvent?
}

/// Shared transport mechanics only; wire schemas remain provider-specific.
enum ChineseASRWebSocket {
    private actor EndState {
        var requested = false
        func request() { requested = true }
    }
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 6 * 60 * 60
        return URLSession(configuration: config)
    }
    static func validateCredential(_ credential: String) throws {
        guard !credential.isEmpty, credential.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              credential.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw ProviderFailure.authorization
        }
    }
    static func seconds(_ raw: Any?) -> Double? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let time = value.doubleValue / 1000
        return time.isFinite && time >= 0 ? time : nil
    }
    static func send(_ message: URLSessionWebSocketTask.Message, to socket: URLSessionWebSocketTask, timeout: TimeInterval = 20) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await socket.send(message) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                socket.cancel(with: .goingAway, reason: nil)
                throw ProviderFailure.connection
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }
    static func receive(from socket: URLSessionWebSocketTask, timeout: Double) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await socket.receive() }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                socket.cancel(with: .goingAway, reason: nil)
                throw ProviderFailure.connection
            }
            defer { group.cancelAll() }
            guard let message = try await group.next() else { throw ProviderFailure.incomplete }
            return message
        }
    }
    static func stream<D: ChineseASRFrameDecoder>(audio: AsyncStream<Data>, socket: URLSessionWebSocketTask,
                                                 endMessage: String, decoder: D,
                                                 writeTimeout: TimeInterval = 20, drainTimeout: TimeInterval = 45,
                                                 emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        let endState = EndState()
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await frame in audio {
                    try Task.checkCancellation()
                    guard frame.count.isMultiple(of: 2) else { throw ProviderFailure.protocolViolation("pcm_alignment") }
                    if !frame.isEmpty { try await send(.data(frame), to: socket, timeout: writeTimeout) }
                }
                try Task.checkCancellation()
                await endState.request()
                // EOS shares the sole audio writer and cannot overtake a queued PCM frame.
                try await send(.string(endMessage), to: socket, timeout: writeTimeout)
                return false
            }
            group.addTask {
                var decoder = decoder
                while true {
                    try Task.checkCancellation()
                    let message = try await socket.receive()
                    if let event = try decoder.consume(ProviderJSON.object(message)) {
                        if event.isComplete {
                            let wasRequested = await endState.requested
                            guard wasRequested else { throw ProviderFailure.incomplete }
                        }
                        try await emit(event)
                        if event.isComplete { return true }
                    }
                }
            }
            defer {
                group.cancelAll()
                socket.cancel(with: .goingAway, reason: nil)
            }
            while let completed = try await group.next() {
                if completed { return }
                // Only starts when all audio and EOS were sent. Active speech has no
                // fixed utterance deadline; finalization has a bounded drain window.
                group.addTask {
                    try await Task.sleep(for: .seconds(drainTimeout))
                    socket.cancel(with: .goingAway, reason: nil)
                    throw ProviderFailure.incomplete
                }
            }
            throw ProviderFailure.incomplete
        }
    }
}
