import Foundation

/// AssemblyAI v3 sends mutable, numbered turns. A provider-final turn is evidence,
/// not an instruction to publish or insert text in another application.
public struct AssemblyStreamingProvider: StreamingASRProvider {
    public init() {}

    static func request(configuration: ModelConfiguration, credential: String) throws -> URLRequest {
        try EnglishProviderSupport.validate(configuration, provider: .assemblyAI, credential: credential)
        guard configuration.context.count <= 1_750 else {
            throw ProviderFailure.configuration("AssemblyAI 话题提示最多为 1750 个字符。")
        }
        let host: String
        switch configuration.region {
        case "global": host = "streaming.assemblyai.com"
        case "us": host = "streaming.us.assemblyai.com"
        case "eu": host = "streaming.eu.assemblyai.com"
        default: throw ProviderFailure.configuration("AssemblyAI 地域须为 global、us 或 eu。")
        }
        var components = URLComponents()
        components.scheme = "wss"; components.host = host; components.path = "/v3/ws"
        components.queryItems = [
            .init(name: "speech_model", value: configuration.model),
            .init(name: "mode", value: "max_accuracy"),
            .init(name: "sample_rate", value: "16000"),
            .init(name: "encoding", value: "pcm_s16le"),
            .init(name: "include_partial_turns", value: "true"),
            .init(name: "language_detection", value: "true"),
            .init(name: "filter_profanity", value: "false")
        ]
        guard let url = components.url else { throw ProviderFailure.configuration("AssemblyAI 连接配置无效。") }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue(credential, forHTTPHeaderField: "Authorization")
        return request
    }

    static func verifyBegin(_ object: [String: Any], configuration: ModelConfiguration) throws -> String? {
        guard object["type"] as? String == "Begin",
              let applied = object["configuration"] as? [String: Any],
              applied["model"] as? String == configuration.model,
              applied["mode"] as? String == "max_accuracy" else {
            throw ProviderFailure.protocolViolation("assembly-applied-model-or-mode")
        }
        return object["id"] as? String
    }

    public func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
                    emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        let request = try Self.request(configuration: configuration, credential: credential)
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        let progress = EnglishAudioProgress()
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
        do {
            try await withTaskCancellationHandler {
                let hello = try await EnglishProviderSupport.firstMessage(socket)
                if hello["error"] != nil { throw ProviderFailure.protocolViolation("assembly-start") }
                let requestID = try Self.verifyBegin(hello, configuration: configuration)
                if !configuration.context.isEmpty {
                    let json = try ProviderJSON.string(["type": "UpdateConfiguration", "prompt": configuration.context])
                    try await EnglishProviderSupport.send(.string(json), to: socket)
                }
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        // Retain 20 ms so every sent frame fits the documented 20–1000 ms range.
                        var pending = Data()
                        for await chunk in audio {
                            try Task.checkCancellation()
                            guard chunk.count % 2 == 0 else { throw ProviderFailure.protocolViolation("pcm-alignment") }
                            pending.append(chunk)
                            while pending.count >= 2_240 {
                                let frame = Data(pending.prefix(1_600)); pending.removeFirst(1_600)
                                try await EnglishProviderSupport.send(.data(frame), to: socket); await progress.sent(frame.count)
                            }
                        }
                        try Task.checkCancellation()
                        if !pending.isEmpty {
                            guard pending.count >= 640 else { throw ProviderFailure.incomplete }
                            try await EnglishProviderSupport.send(.data(pending), to: socket); await progress.sent(pending.count)
                        }
                        await progress.endInput()
                        try await EnglishProviderSupport.send(.string("{\"type\":\"Terminate\"}"), to: socket)
                        try await Task.sleep(for: .seconds(45))
                        socket.cancel(with: .goingAway, reason: nil)
                        throw ProviderFailure.incomplete
                    }
                    group.addTask {
                        var transcript = AssemblyTranscriptAccumulator(requestID: requestID)
                        while true {
                            try Task.checkCancellation()
                            let object = try ProviderJSON.object(try await socket.receive())
                            if object["error"] != nil { throw ProviderFailure.protocolViolation("assembly-error") }
                            switch object["type"] as? String {
                            case "Turn":
                                let event = try transcript.accept(object, duration: await progress.duration)
                                try await emit(event)
                            case "Termination":
                                guard await progress.inputEnded else { throw ProviderFailure.incomplete }
                                // Termination alone cannot make an unfinished turn stable.
                                guard transcript.allTurnsFinal else { throw ProviderFailure.incomplete }
                                try await emit(transcript.event(duration: await progress.duration, complete: true))
                                return
                            default: break // SpeechStarted, Heartbeat and optional speaker metadata.
                            }
                        }
                    }
                    defer { group.cancelAll(); socket.cancel(with: .normalClosure, reason: nil) }
                    try await group.next()
                }
            } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
        } catch {
            throw EnglishProviderSupport.failure(error, socket: socket)
        }
    }
}

struct AssemblyTranscriptAccumulator {
    struct Turn {
        var text: String
        var isFinal: Bool
        var stableUTF16Length: Int
        var hasWordAlignment: Bool
        var tokens: [ProviderToken]
        var language: String?
    }
    private var turns: [Int: Turn] = [:]
    let requestID: String?
    // Keep construction internal across Swift versions; private stored state
    // otherwise makes the synthesized memberwise initializer private.
    init(requestID: String?) { self.requestID = requestID }
    var allTurnsFinal: Bool {
        turns.values.allSatisfy(\.isFinal) && turns.keys.sorted() == Array(0..<turns.count)
    }

    mutating func accept(_ object: [String: Any], duration: Double) throws -> ProviderTranscriptEvent {
        guard let order = object["turn_order"] as? Int, order >= 0, order < 100_000,
              let text = object["transcript"] as? String, text.utf16.count <= 1_000_000,
              let final = object["end_of_turn"] as? Bool else {
            throw ProviderFailure.protocolViolation("assembly-turn")
        }
        // Pro emits a fully formatted final. Do not prematurely commit an
        // unformatted end-of-turn message, or make missing flags mean true.
        let complete = final && object["turn_is_formatted"] as? Bool == true
        let language = object["language_code"] as? String
        let tokens = try EnglishProviderSupport.words(object["words"], scale: 0.001, final: complete, language: language)
        // Use an internal text map for UTF-16 stability, but persist original
        // word text and timing. Fusion owns the single cross-provider span map.
        let mapped = EnglishProviderSupport.align(tokens, to: text, utteranceFinal: complete)
        let stable = complete ? text.utf16.count : (mapped?.prefix(while: \.isFinal).reduce(0) { $0 + $1.text.utf16.count } ?? 0)
        turns[order] = Turn(text: text, isFinal: complete, stableUTF16Length: stable,
            hasWordAlignment: mapped != nil, tokens: tokens, language: language)
        return event(duration: duration)
    }

    func event(duration: Double, complete: Bool = false) -> ProviderTranscriptEvent {
        var text = "", stable = 0, prefixFinal = true, expectedOrder = 0
        var tokens: [ProviderToken] = [], languages = Set<String>(), allTextAligned = true
        for order in turns.keys.sorted() {
            guard let turn = turns[order] else { continue }
            if order != expectedOrder { prefixFinal = false }
            expectedOrder = order + 1
            let priorLength = text.utf16.count
            text = EnglishProviderSupport.join(text, turn.text)
            let separatorLength = text.utf16.count - priorLength - turn.text.utf16.count
            if prefixFinal, turn.stableUTF16Length > 0 {
                stable = priorLength + separatorLength + turn.stableUTF16Length
            }
            if !turn.isFinal { prefixFinal = false }
            allTextAligned = allTextAligned && turn.hasWordAlignment
            tokens.append(contentsOf: turn.tokens)
            if let language = turn.language { languages.insert(language) }
        }
        let end = tokens.map(\.endSeconds).max() ?? duration
        return ProviderTranscriptEvent(text: text, stableUTF16Length: stable,
            audioEndSeconds: max(0, end), timingGranularity: tokens.isEmpty || !allTextAligned ? "utterance" : "word",
            language: languages.count == 1 ? languages.first : nil, isComplete: complete,
            requestID: requestID, tokens: tokens)
    }
}

actor EnglishAudioProgress {
    private var bytes = 0
    private(set) var inputEnded = false
    var duration: Double { Double(bytes) / 32_000 }
    func sent(_ count: Int) { bytes += count }
    func endInput() { inputEnded = true }
}

enum EnglishProviderSupport {
    static func validate(_ configuration: ModelConfiguration, provider: CloudProvider, credential: String) throws {
        try configuration.validate()
        guard configuration.provider == provider, configuration.cloudConsent else {
            throw ProviderFailure.configuration("请检查服务配置并授权此服务处理音频。")
        }
        guard !credential.isEmpty, credential.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw ProviderFailure.authorization
        }
    }

    static func firstMessage(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        let deadline = Task {
            try await Task.sleep(for: .seconds(25))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { deadline.cancel() }
        return try ProviderJSON.object(try await socket.receive())
    }

    static func send(_ message: URLSessionWebSocketTask.Message, to socket: URLSessionWebSocketTask) async throws {
        let deadline = Task {
            try await Task.sleep(for: .seconds(25))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { deadline.cancel() }
        try await socket.send(message)
    }

    static func failure(_ error: Error, socket: URLSessionWebSocketTask? = nil) -> ProviderFailure {
        if Task.isCancelled || error is CancellationError { return .cancelled }
        if let failure = error as? ProviderFailure { return failure }
        if let code = (socket?.response as? HTTPURLResponse)?.statusCode, code != 101 {
            return .http(code)
        }
        return .connection
    }

    /// Segment separators are layout, never a text-overlap deduplication heuristic.
    /// Repeating "yes" in consecutive turns remains "yes yes".
    static func join(_ prior: String, _ next: String) -> String {
        guard !prior.isEmpty else { return next }
        guard !next.isEmpty else { return prior }
        if prior.last?.isWhitespace == true || next.first?.isWhitespace == true { return prior + next }
        return prior + " " + next
    }

    static func words(_ value: Any?, scale: Double, final: Bool, language: String?) throws -> [ProviderToken] {
        guard let value else { return [] }
        guard let words = value as? [[String: Any]] else { throw ProviderFailure.protocolViolation("word-list") }
        let tokens: [ProviderToken] = try words.compactMap { word in
            if let kind = word["type"] as? String, kind != "word" && kind != "spacing" { return nil }
            guard let text = word["text"] as? String,
                  let start = word["start"] as? Double, let end = word["end"] as? Double,
                  start.isFinite, end.isFinite, start >= 0, end >= start else {
                throw ProviderFailure.protocolViolation("word-timestamp")
            }
            let confidence = word["confidence"] as? Double
            return ProviderToken(text: text, startSeconds: start * scale, endSeconds: end * scale,
                isFinal: (word["word_is_final"] as? Bool) ?? final,
                language: (word["language_code"] as? String) ?? language,
                rawConfidence: confidence?.isFinite == true ? confidence : nil)
        }
        return tokens
    }

    /// Temporary text map used only to calculate stable UTF-16 positions. Copy
    /// original separators locally without modifying persisted raw word tokens.
    /// Timestamps remain the actual spoken word's timestamps.
    /// A normalization mismatch or an unrepresented spoken word downgrades this
    /// candidate to utterance timing instead of silently dropping its text.
    static func align(_ tokens: [ProviderToken], to transcript: String, utteranceFinal: Bool) -> [ProviderToken]? {
        guard !tokens.isEmpty else { return transcript.isEmpty ? [] : nil }
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var cursor = transcript.startIndex, result: [ProviderToken] = []
        for token in tokens {
            guard !token.text.isEmpty,
                  let range = transcript.range(of: token.text, options: .literal, range: cursor..<transcript.endIndex) else { return nil }
            let gap = String(transcript[cursor..<range.lowerBound])
            guard gap.unicodeScalars.allSatisfy({ separators.contains($0) }) else { return nil }
            var aligned = token
            aligned.text = gap + String(transcript[range])
            if !utteranceFinal && !gap.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                aligned.isFinal = false
            }
            result.append(aligned); cursor = range.upperBound
        }
        let tail = String(transcript[cursor...])
        guard tail.unicodeScalars.allSatisfy({ separators.contains($0) }) else { return nil }
        result[result.count - 1].text += tail
        if !utteranceFinal && !tail.isEmpty { result[result.count - 1].isFinal = false }
        guard result.map(\.text).joined() == transcript else { return nil }
        return result
    }
}
