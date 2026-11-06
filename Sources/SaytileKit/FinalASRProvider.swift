import Foundation

/// Completed-audio transcription. This never claims file-upload response streaming
/// is a realtime microphone protocol. Only the coordinator may publish its result.
public struct FinalASRProvider: Sendable {
    public init() {}

    public func transcribe(pcm: Data, configuration: ModelConfiguration, credential: String) async throws -> ProviderTranscriptEvent {
        let request = try Self.request(pcm: pcm, configuration: configuration, credential: credential)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ProviderFailure.connection }
            guard (200..<300).contains(response.statusCode) else { throw ProviderFailure.http(response.statusCode) }
            return try Self.parse(data, provider: configuration.provider, duration: Double(pcm.count) / 32_000,
                requestID: response.value(forHTTPHeaderField: "x-request-id") ?? response.value(forHTTPHeaderField: "request-id"))
        } catch { throw EnglishProviderSupport.failure(error) }
    }

    static func request(pcm: Data, configuration: ModelConfiguration, credential: String,
                        boundary: String = "Saytile-" + UUID().uuidString) throws -> URLRequest {
        guard [.elevenLabsFile, .openAITranscription].contains(configuration.provider),
              configuration.purpose == .finalASR else { throw ProviderFailure.configuration("请选择支持的文件识别服务。") }
        try EnglishProviderSupport.validate(configuration, provider: configuration.provider, credential: credential)
        guard configuration.region == "global" else {
            throw ProviderFailure.configuration("当前文件识别适配器仅支持 global 端点。")
        }
        // 12 MB is a per-review allocation bound, not a cost or model-quality policy.
        // Larger recordings are reviewed in audio-aligned windows by the caller.
        guard pcm.count >= 3_200, pcm.count <= 12_000_000, pcm.count % 2 == 0 else {
            throw ProviderFailure.configuration("复核音频须为 100 毫秒至 12 MB 的完整 PCM16 片段；长录音请分段复核。")
        }
        guard boundary.range(of: "^[A-Za-z0-9-]{1,100}$", options: .regularExpression) != nil else {
            throw ProviderFailure.configuration("文件请求分隔符无效。")
        }
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let endpoint: String
        let file: Data
        let filename: String
        let contentType: String
        if configuration.provider == .elevenLabsFile {
            endpoint = "https://api.elevenlabs.io/v1/speech-to-text"
            field("model_id", configuration.model)
            field("timestamps_granularity", "word")
            field("diarize", "false")
            field("tag_audio_events", "false")
            field("file_format", "pcm_s16le_16")
            file = pcm; filename = "audio.pcm"; contentType = "application/octet-stream"
        } else {
            endpoint = "https://api.openai.com/v1/audio/transcriptions"
            field("model", configuration.model)
            // The current gpt-transcribe workflow returns JSON by default.
            if !configuration.context.isEmpty { field("prompt", configuration.context) }
            file = PCMJournal.header(frames: Int64(pcm.count / 2)) + pcm
            filename = "audio.wav"; contentType = "audio/wav"
        }
        // No forced language, text-edit option, filler removal or invented timestamp request.
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        body.append(file); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"; request.timeoutInterval = 300
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.provider == .elevenLabsFile ? credential : "Bearer \(credential)",
            forHTTPHeaderField: configuration.provider == .elevenLabsFile ? "xi-api-key" : "Authorization")
        request.httpBody = body
        return request
    }

    static func parse(_ data: Data, provider: CloudProvider, duration: Double, requestID: String?) throws -> ProviderTranscriptEvent {
        guard data.count <= 8_000_000,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else { throw ProviderFailure.protocolViolation("file-transcript") }
        let languages = object["languages"] as? [[String: Any]]
        let singleLanguage = languages?.count == 1 ? languages?.first?["code"] as? String : nil
        let language = (object["language_code"] as? String) ?? (object["language"] as? String) ?? singleLanguage
        let words = try EnglishProviderSupport.words(object["words"], scale: 1, final: true, language: language)
        let aligned = EnglishProviderSupport.align(words, to: text, utteranceFinal: true) != nil
        return ProviderTranscriptEvent(text: text, stableUTF16Length: text.utf16.count,
            audioEndSeconds: duration, timingGranularity: words.isEmpty || !aligned ? "utterance" : "word",
            language: language, isComplete: true, requestID: requestID, tokens: words)
    }
}
