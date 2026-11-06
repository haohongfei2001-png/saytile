import Foundation
import CoreFoundation

/// Qwen Message is an actual duplex PCM service. Intermediate results are explicitly
/// enabled: the model's default message-oriented response is not a live-text contract.
public struct QwenMessageProvider: StreamingASRProvider {
    public init() {}

    public func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
                    emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        let taskID = UUID().uuidString
        let request = try QwenMessageCodec.request(configuration: configuration, credential: credential)
        let start = try QwenMessageCodec.startMessage(configuration: configuration, taskID: taskID)
        let finish = try QwenMessageCodec.finishMessage(taskID: taskID)
        let session = ChineseASRWebSocket.makeSession()
        let socket = session.webSocketTask(with: request)
        defer { socket.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            socket.resume()
            try await ChineseASRWebSocket.send(.string(start), to: socket)
            var codec = QwenMessageCodec(taskID: taskID)
            let first = try await ChineseASRWebSocket.receive(from: socket, timeout: 20)
            _ = try codec.consume(ProviderJSON.object(first))
            guard codec.hasStarted else { throw ProviderFailure.protocolViolation("qwen_ready") }
            try await ChineseASRWebSocket.stream(audio: audio, socket: socket, endMessage: finish,
                                                decoder: codec, emit: emit)
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
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
            if code.contains("auth") || code.contains("apikey") || code.contains("accessdenied") || code.contains("forbidden") {
                throw ProviderFailure.authorization
            }
            if code.contains("quota") || code.contains("limit") || code.contains("balance") || code.contains("arrear") {
                throw ProviderFailure.quota
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
            guard hasStarted, segments.values.allSatisfy({ $0.text.isEmpty || $0.isFinal }) else {
                throw ProviderFailure.incomplete
            }
            isComplete = true
            return snapshot()
        default:
            throw ProviderFailure.protocolViolation("qwen_event")
        }
    }

    private mutating func update(_ sentence: [String: Any], finalKey: String?) throws -> Int {
        guard let id = sentence["sentence_id"] as? Int, id >= 0,
              let text = sentence["text"] as? String else {
            throw ProviderFailure.protocolViolation("qwen_segment")
        }
        let final = finalKey.flatMap { sentence[$0] as? Bool } ?? false
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
        var text = "", stable = 0, stableOpen = true, previousID: Int?
        var tokens: [ProviderToken] = [], fullyTimed = true, hasSentenceTokens = false
        for (id, segment) in ordered {
            if let previousID, id != previousID + 1 { stableOpen = false }
            previousID = id
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
    static func send(_ message: URLSessionWebSocketTask.Message, to socket: URLSessionWebSocketTask) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await socket.send(message) }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
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
                                                 emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        let endState = EndState()
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await frame in audio {
                    try Task.checkCancellation()
                    guard frame.count.isMultiple(of: 2) else { throw ProviderFailure.protocolViolation("pcm_alignment") }
                    if !frame.isEmpty { try await send(.data(frame), to: socket) }
                }
                try Task.checkCancellation()
                await endState.request()
                // EOS shares the sole audio writer and cannot overtake a queued PCM frame.
                try await send(.string(endMessage), to: socket)
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
                    try await Task.sleep(for: .seconds(45))
                    socket.cancel(with: .goingAway, reason: nil)
                    throw ProviderFailure.incomplete
                }
            }
            throw ProviderFailure.incomplete
        }
    }
}
