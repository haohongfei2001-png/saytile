import Foundation
import CoreFoundation

/// ENDPOINTING turns may finish out of order. Session completion additionally
/// requires a successful endStream send, a normal close and every turn completed.
public struct MetaStreamingProvider: StreamingASRProvider {
    public init() {}

    static func request(configuration: ModelConfiguration, credential: String) throws -> URLRequest {
        try EnglishProviderSupport.validate(configuration, provider: .meta, credential: credential)
        guard configuration.region == "global", configuration.model == "muse-voice-transcribe-1.0" else {
            throw ProviderFailure.configuration("此适配器支持 Meta global 的 muse-voice-transcribe-1.0 实时接口。")
        }
        // Meta explicitly ignores HTTP Authorization for this endpoint.
        return URLRequest(url: URL(string: "wss://api.meta.ai/v1/asr/realtime")!, timeoutInterval: 25)
    }

    static func handshake(configuration: ModelConfiguration, credential: String) throws -> String {
        _ = try request(configuration: configuration, credential: credential)
        // Generic topic prose is not a language/keyword list; it remains available
        // to the text arbitrator, not silently reinterpreted for this provider.
        return try ProviderJSON.string([
            "authorization": ["accessToken": "Bearer " + credential],
            "model": configuration.model, "audioEncoding": "PCM_16KHZ",
            "mode": "ENDPOINTING", "partialMode": "CUMULATIVE",
            "languageBias": ["Mandarin Chinese", "English"], "emitAudioProgress": true
        ])
    }

    static func sessionID(_ object: [String: Any]) throws -> String {
        if object["type"] as? String == "error" { throw MetaTranscriptAccumulator.error(object) }
        guard object["type"] == nil, let id = object["sessionId"] as? String, !id.isEmpty else {
            throw ProviderFailure.protocolViolation("meta-handshake")
        }
        return id
    }

    public func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
                    emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        let request = try Self.request(configuration: configuration, credential: credential)
        let hello = try Self.handshake(configuration: configuration, credential: credential)
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        let progress = EnglishAudioProgress()
        defer { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
        do {
            try await withTaskCancellationHandler {
                socket.resume()
                // First application frame, before any PCM.
                try await EnglishProviderSupport.send(.string(hello), to: socket)
                let id = try Self.sessionID(try await EnglishProviderSupport.firstMessage(socket))
                try await withThrowingTaskGroup(of: MetaWorkerResult.self) { group in
                    group.addTask {
                        let clock = ContinuousClock()
                        var nextFrame = clock.now, pending = Data()
                        for await chunk in audio {
                            try Task.checkCancellation()
                            guard chunk.count % 2 == 0 else { throw ProviderFailure.protocolViolation("pcm-alignment") }
                            pending.append(chunk)
                            while pending.count >= 640 {
                                let frame = Data(pending.prefix(640)); pending.removeFirst(640)
                                // Pace recovery data too. Limit catch-up after a stall to
                                // 80 ms, well below the server's five-second backlog cap.
                                nextFrame = max(nextFrame, clock.now.advanced(by: .milliseconds(-80)))
                                try await clock.sleep(until: nextFrame, tolerance: .milliseconds(1))
                                try await EnglishProviderSupport.send(.data(frame), to: socket)
                                await progress.sent(frame.count)
                                nextFrame = nextFrame.advanced(by: .milliseconds(20))
                            }
                        }
                        try Task.checkCancellation()
                        if !pending.isEmpty {
                            nextFrame = max(nextFrame, clock.now.advanced(by: .milliseconds(-80)))
                            try await clock.sleep(until: nextFrame, tolerance: .milliseconds(1))
                            try await EnglishProviderSupport.send(.data(pending), to: socket)
                            await progress.sent(pending.count)
                        }
                        // Mark the attempt before sending; .inputEnded below proves
                        // the actual endStream write succeeded before final publication.
                        await progress.endInput()
                        try await EnglishProviderSupport.send(.string("{\"type\":\"endStream\"}"), to: socket)
                        return .inputEnded
                    }
                    group.addTask {
                        var decoder = MetaTranscriptAccumulator(requestID: id)
                        while true {
                            try Task.checkCancellation()
                            let frame: URLSessionWebSocketTask.Message
                            do { frame = try await socket.receive() }
                            catch {
                                try Task.checkCancellation()
                                guard socket.closeCode == .normalClosure else { throw Self.closeFailure(socket.closeCode) }
                                guard await progress.inputEnded else { throw ProviderFailure.incomplete }
                                return .serverClosed(decoder)
                            }
                            let object = try ProviderJSON.object(frame)
                            if let event = try decoder.accept(object) { try await emit(event) }
                        }
                    }
                    var sentEnd = false
                    var closed: MetaTranscriptAccumulator?
                    defer { group.cancelAll(); socket.cancel(with: .normalClosure, reason: nil) }
                    while let result = try await group.next() {
                        switch result {
                        case .inputEnded:
                            sentEnd = true
                            group.addTask {
                                try await Task.sleep(for: .seconds(45))
                                socket.cancel(with: .goingAway, reason: nil)
                                throw ProviderFailure.incomplete
                            }
                        case .serverClosed(let decoder): closed = decoder
                        }
                        if sentEnd, let closed {
                            let complete = try closed.completedEvent(endStreamSent: true, normalClose: true,
                                                                     duration: await progress.duration)
                            try await emit(complete)
                            return
                        }
                    }
                    throw ProviderFailure.incomplete
                }
            } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
        } catch { throw EnglishProviderSupport.failure(error, socket: socket) }
    }

    static func closeFailure(_ code: URLSessionWebSocketTask.CloseCode) -> ProviderFailure {
        switch code.rawValue {
        case 1008: return .configuration("Meta 请求参数或实时音频发送节奏被拒绝；请检查模型配置与连接。")
        case 1013: return .quota
        default: return .connection
        }
    }
}

private enum MetaWorkerResult: Sendable {
    case inputEnded
    case serverClosed(MetaTranscriptAccumulator)
}

struct MetaTranscriptAccumulator: Sendable {
    struct Turn: Sendable {
        var start: Double
        var end: Double?
        var latestProgress: Double
        var text = ""
        var complete = false
    }
    let requestID: String
    private var turns: [Int: Turn] = [:]
    private var order: [Int] = []
    private var activeTurn: Int?
    private var processedSeconds: Double = 0

    // Explicit access avoids relying on memberwise synthesis for private state.
    init(requestID: String) { self.requestID = requestID }

    mutating func accept(_ object: [String: Any]) throws -> ProviderTranscriptEvent? {
        guard let type = object["type"] as? String else { throw ProviderFailure.protocolViolation("meta-event") }
        switch type {
        case "error": throw Self.error(object)
        case "speechStart":
            let id = try Self.turnID(object), time = try Self.time(object)
            guard turns[id] == nil else { throw ProviderFailure.protocolViolation("meta-duplicate-turn") }
            turns[id] = Turn(start: time, end: nil, latestProgress: time)
            order.append(id); activeTurn = id; processedSeconds = max(processedSeconds, time)
        case "transcript":
            // Late completion of an older turn must not steal the current partial.
            guard let id = activeTurn, var turn = turns[id], !turn.complete else {
                throw ProviderFailure.protocolViolation("meta-partial-turn")
            }
            let time = try Self.time(object)
            guard time >= turn.start else { throw ProviderFailure.protocolViolation("meta-time") }
            turn.text = try Self.text(object); turn.latestProgress = time
            turns[id] = turn; processedSeconds = max(processedSeconds, time)
            // `final` is not a completion signal in ENDPOINTING mode.
        case "speechEnd":
            let id = try Self.turnID(object), time = try Self.time(object)
            guard var turn = turns[id], !turn.complete, time >= turn.start else {
                throw ProviderFailure.protocolViolation("meta-end-turn")
            }
            turn.end = time; turn.latestProgress = max(turn.latestProgress, time)
            turns[id] = turn; processedSeconds = max(processedSeconds, time)
        case "speechComplete":
            let id = try Self.turnID(object), time = try Self.time(object)
            guard var turn = turns[id], !turn.complete, let end = turn.end, time >= end else {
                throw ProviderFailure.protocolViolation("meta-complete-turn")
            }
            turn.text = try Self.text(object); turn.complete = true
            turn.latestProgress = max(turn.latestProgress, time)
            turns[id] = turn; processedSeconds = max(processedSeconds, time)
        case "audioProgress":
            processedSeconds = max(processedSeconds, try Self.time(object))
            return nil
        default: return nil
        }
        return snapshot()
    }

    func completedEvent(endStreamSent: Bool, normalClose: Bool, duration: Double) throws -> ProviderTranscriptEvent {
        guard endStreamSent, normalClose, turns.values.allSatisfy(\.complete),
              duration.isFinite, duration >= 0, processedSeconds <= duration + 0.08 else { throw ProviderFailure.incomplete }
        var event = snapshot()
        event.isComplete = true; event.audioEndSeconds = duration
        return event
    }

    private func snapshot() -> ProviderTranscriptEvent {
        var text = "", stable = 0, stableOpen = true, tokens: [ProviderToken] = []
        for id in order {
            guard let turn = turns[id] else { continue }
            text = EnglishProviderSupport.join(text, turn.text)
            if !turn.complete { stableOpen = false }
            if stableOpen { stable = text.utf16.count }
            if !turn.text.isEmpty {
                tokens.append(ProviderToken(text: turn.text, startSeconds: turn.start,
                    endSeconds: turn.end ?? turn.latestProgress, isFinal: turn.complete))
            }
        }
        // Official schemas label these processing-progress times, not precise
        // acoustic boundaries. Retain the evidence without enabling word splicing.
        return ProviderTranscriptEvent(text: text, stableUTF16Length: stable,
            audioEndSeconds: processedSeconds, timingGranularity: "turn-progress",
            requestID: requestID, tokens: tokens)
    }

    static func error(_ object: [String: Any]) -> ProviderFailure {
        let code = ((object["errorType"] as? String ?? "") + " " + (object["errorCode"] as? String ?? "")).lowercased()
        if code.contains("auth") || code.contains("api_key") || code.contains("permission") { return .authorization }
        if code.contains("rate_limit") || code.contains("quota") { return .quota }
        if code.contains("invalid_request") || code.contains("invalid_model") {
            return .configuration("Meta 请求参数或型号不受支持。")
        }
        return .connection // Never expose arbitrary provider messages or credentials.
    }

    private static func text(_ object: [String: Any]) throws -> String {
        guard let text = object["transcript"] as? String, text.utf16.count <= 1_000_000 else {
            throw ProviderFailure.protocolViolation("meta-text")
        }
        return text
    }
    private static func turnID(_ object: [String: Any]) throws -> Int {
        guard let number = object["turnId"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= Double(Int32.min), number.doubleValue <= Double(Int32.max) else {
            throw ProviderFailure.protocolViolation("meta-turn-id")
        }
        return number.intValue
    }
    private static func time(_ object: [String: Any]) throws -> Double {
        guard let number = object["audioProcessedMs"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0 else {
            throw ProviderFailure.protocolViolation("meta-progress-time")
        }
        return number.doubleValue / 1_000
    }
}
