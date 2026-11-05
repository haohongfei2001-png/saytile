import Foundation
@preconcurrency import Speech
@preconcurrency import AVFoundation

public struct SpeechAvailability: Sendable {
    public let supported: Bool
    public let installed: Bool
    public let message: String
}

public enum AppleSpeechService {
    public static func availability() async -> SpeechAvailability {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN")) else {
            return .init(supported: false, installed: false, message: "此 Mac 暂不支持中文 Apple Speech")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let state = await AssetInventory.status(forModules: [transcriber])
        return .init(supported: true, installed: state == .installed, message: state == .installed ? "中文识别已就绪 · 在设备上处理" : "需要下载 Apple 中文识别资源")
    }
    public static func prepare() async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN")) else { throw AudioFailure.message("Apple Speech 不支持中文") }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        _ = try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await request.downloadAndInstall() }
    }
}

/// Input is bounded independently of capture. Slow / failed ASR never owns the recorder queue.
final class LiveSpeechSession: @unchecked Sendable {
    private let continuation: AsyncStream<Data>.Continuation
    private let task: Task<Void, Never>
    private let ticket: RecognitionTicket
    private let store: SaytileStore
    init(store: SaytileStore, ticket: RecognitionTicket) {
        self.store = store; self.ticket = ticket
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(300))
        self.continuation = continuation
        self.task = Task {
            do { try await Self.recognize(stream: stream, store: store, ticket: ticket) }
            catch { try? await store.failRecognition(ticket: ticket, message: error.localizedDescription) }
        }
    }
    func append(_ data: Data) {
        if case .dropped = continuation.yield(data) {
            continuation.finish(); task.cancel()
            Task { try? await store.failRecognition(ticket: ticket, message: "识别处理跟不上，原音已保留，可稍后重新识别") }
        }
    }
    func finish() {
        continuation.finish()
        let active = task
        Task { try? await Task.sleep(for: .seconds(20)); active.cancel() }
    }
    func cancel() { continuation.finish(); task.cancel() }
    func wait() async { await task.value }
    private static func recognize(stream: AsyncStream<Data>, store: SaytileStore, ticket: RecognitionTicket) async throws {
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN")) else { throw AudioFailure.message("此设备的 Apple 中文识别不可用；原音已保存") }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let detector = SpeechDetector()
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw AudioFailure.message("请在设置下载中文识别资源；原音已保存") }
        let modules: [any SpeechModule] = [transcriber, detector]
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules),
              let source = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: format) else { throw AudioFailure.message("无法创建语音格式转换器") }
        let analyzer = SpeechAnalyzer(modules: modules)
        let (inputs, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(300))
        let resultTask = Task {
            var pieces: [Double: (String, Bool, Double)] = [:]
            var hasText = false
            for try await result in transcriber.results {
                let start = result.range.start.seconds
                let end = CMTimeRangeGetEnd(result.range).seconds
                // A later hypothesis replaces the same audio range, never appends duplicate revisions.
                pieces = pieces.filter { !($0.key < end && $0.value.2 > start) }
                pieces[start] = (String(result.text.characters), result.isFinal, end)
                let sorted = pieces.sorted { $0.key < $1.key }
                let text = sorted.map { $0.value.0 }.joined()
                if !text.isEmpty { hasText = true; _ = try await store.applyRecognition(ticket: ticket, text: text, isFinal: sorted.allSatisfy { $0.value.1 }) }
            }
            if !hasText { throw AudioFailure.message("未识别到文字；原音可回听或重试") }
            try await store.finishRecognition(ticket: ticket)
        }
        try await withTaskCancellationHandler {
        do {
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: inputs)
            for await data in stream {
                try Task.checkCancellation()
                let count = data.count / 2
                guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(count)),
                      let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(count) * format.sampleRate / 16_000) + 32)) else { continue }
                buffer.frameLength = AVAudioFrameCount(count)
                data.copyBytes(to: UnsafeMutableRawBufferPointer(start: buffer.int16ChannelData![0], count: data.count))
                var supplied = false
                var conversionError: NSError?
                let status = converter.convert(to: output, error: &conversionError) { _, state in
                    if supplied { state.pointee = .noDataNow; return nil }
                    supplied = true; state.pointee = .haveData; return buffer
                }
                if status == .error { throw conversionError ?? AudioFailure.message("识别音频转换失败") as NSError }
                if output.frameLength > 0, case .dropped = inputContinuation.yield(AnalyzerInput(buffer: output)) { throw AudioFailure.message("识别音频队列已满；可从原音重试") }
            }
            inputContinuation.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await resultTask.value
        } catch {
            inputContinuation.finish(); await analyzer.cancelAndFinishNow(); resultTask.cancel()
            throw error
        }
        } onCancel: { Task { await analyzer.cancelAndFinishNow() } }
    }
}
