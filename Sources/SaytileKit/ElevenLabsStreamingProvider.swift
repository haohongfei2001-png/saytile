import Foundation

/// Optional Scribe realtime adapter. Manual commit is tied to the original audio
/// segment boundary. Partials remain revisable until that commit; its delayed
/// timestamp message updates the same candidate rather than appending it twice.
public struct ElevenLabsStreamingProvider: StreamingASRProvider {
    public init() {}

    static func request(configuration: ModelConfiguration, credential: String) throws -> URLRequest {
        try EnglishProviderSupport.validate(configuration, provider: .elevenLabsRealtime, credential: credential)
        guard configuration.region == "global" else {
            throw ProviderFailure.configuration("当前 ElevenLabs 适配器仅支持 global 端点。")
        }
        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        components.queryItems = [
            .init(name: "model_id", value: configuration.model),
            .init(name: "audio_format", value: "pcm_16000"),
            .init(name: "commit_strategy", value: "manual"),
            .init(name: "include_timestamps", value: "true"),
            .init(name: "include_language_detection", value: "true"),
            .init(name: "no_verbatim", value: "false")
        ]
        guard let url = components.url else { throw ProviderFailure.configuration("ElevenLabs 连接配置无效。") }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue(credential, forHTTPHeaderField: "xi-api-key")
        return request
    }

    public func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
                    emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: try Self.request(configuration: configuration, credential: credential))
        let progress = EnglishAudioProgress()
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
        do {
            try await withTaskCancellationHandler {
                let hello = try await EnglishProviderSupport.firstMessage(socket)
                try Self.checkError(hello)
                guard hello["message_type"] as? String == "session_started" else {
                    throw ProviderFailure.protocolViolation("scribe-session")
                }
                let requestID = hello["session_id"] as? String
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        var pending = Data()
                        for await chunk in audio {
                            try Task.checkCancellation()
                            guard chunk.count % 2 == 0 else { throw ProviderFailure.protocolViolation("pcm-alignment") }
                            pending.append(chunk)
                            while pending.count >= 3_200 {
                                let frame = Data(pending.prefix(3_200)); pending.removeFirst(3_200)
                                try await socket.send(.string(try Self.audioMessage(frame, commit: false)))
                                await progress.sent(frame.count)
                            }
                        }
                        try Task.checkCancellation()
                        guard await progress.duration + Double(pending.count) / 32_000 >= 0.1 else {
                            throw ProviderFailure.incomplete
                        }
                        // No second audio writer can interleave this final frame/commit.
                        await progress.sent(pending.count); await progress.endInput()
                        try await socket.send(.string(try Self.audioMessage(pending, commit: true)))
                        try await Task.sleep(for: .seconds(45))
                        socket.cancel(with: .goingAway, reason: nil)
                        throw ProviderFailure.incomplete
                    }
                    group.addTask {
                        var transcript = ElevenLabsTranscriptAccumulator(requestID: requestID)
                        while true {
                            try Task.checkCancellation()
                            let object = try ProviderJSON.object(try await socket.receive())
                            try Self.checkError(object)
                            if let event = try transcript.accept(object, duration: await progress.duration,
                                                                  inputEnded: await progress.inputEnded) {
                                try await emit(event)
                                if event.isComplete { return }
                            }
                        }
                    }
                    defer { group.cancelAll(); socket.cancel(with: .normalClosure, reason: nil) }
                    try await group.next()
                }
            } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
        } catch { throw EnglishProviderSupport.failure(error, socket: socket) }
    }

    static func audioMessage(_ pcm: Data, commit: Bool) throws -> String {
        try ProviderJSON.string(["message_type": "input_audio_chunk", "audio_base_64": pcm.base64EncodedString(),
                                 "sample_rate": 16_000, "commit": commit])
    }

    static func checkError(_ object: [String: Any]) throws {
        guard let kind = object["message_type"] as? String else { throw ProviderFailure.protocolViolation("scribe-message") }
        switch kind {
        case "auth_error", "unaccepted_terms": throw ProviderFailure.authorization
        case "quota_exceeded", "rate_limited", "throttled", "resource_exhausted": throw ProviderFailure.quota
        case "error", "input_error", "invalid_request", "chunk_size_exceeded", "queue_overflow",
             "session_time_limit_exceeded", "insufficient_audio_activity", "transcriber_error":
            throw ProviderFailure.protocolViolation("scribe-" + kind)
        default: break
        }
    }
}

struct ElevenLabsTranscriptAccumulator {
    let requestID: String?
    private(set) var committedText: String?
    private var timedText: String?

    mutating func accept(_ object: [String: Any], duration: Double, inputEnded: Bool) throws -> ProviderTranscriptEvent? {
        guard let kind = object["message_type"] as? String else { throw ProviderFailure.protocolViolation("scribe-message") }
        guard ["partial_transcript", "committed_transcript", "committed_transcript_with_timestamps"].contains(kind) else { return nil }
        guard let text = object["text"] as? String, text.utf16.count <= 1_000_000 else {
            throw ProviderFailure.protocolViolation("scribe-transcript")
        }
        if kind == "partial_transcript" {
            // Once committed, a keepalive cannot retract or duplicate the candidate.
            guard committedText == nil, timedText == nil else { return nil }
            return ProviderTranscriptEvent(text: text, audioEndSeconds: duration, requestID: requestID)
        }
        // Manual mode emits exactly one commit for this run. An unexpected earlier
        // commit is not safe to reinterpret as a recording-complete response.
        guard inputEnded else { throw ProviderFailure.protocolViolation("scribe-early-commit") }
        if kind == "committed_transcript" {
            if let committedText, committedText != text { throw ProviderFailure.protocolViolation("scribe-duplicate-commit") }
            if let timedText, timedText != text { throw ProviderFailure.protocolViolation("scribe-timing-mismatch") }
            committedText = text
            return ProviderTranscriptEvent(text: text, stableUTF16Length: text.utf16.count,
                audioEndSeconds: duration, requestID: requestID)
        }
        if let committedText, committedText != text { throw ProviderFailure.protocolViolation("scribe-timing-mismatch") }
        timedText = text
        let language = object["language_code"] as? String
        let tokens = try EnglishProviderSupport.words(object["words"], scale: 1, final: true, language: language)
        return ProviderTranscriptEvent(text: text, stableUTF16Length: text.utf16.count,
            audioEndSeconds: duration, timingGranularity: tokens.isEmpty ? "utterance" : "word",
            language: language, isComplete: true, requestID: requestID, tokens: tokens)
    }
}
