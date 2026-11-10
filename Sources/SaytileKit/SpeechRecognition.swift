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
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await withTaskCancellationHandler { try await request.downloadAndInstall() }
            onCancel: { request.progress.cancel() }
        }
    }
}

/// Input is bounded independently of capture. Slow / failed ASR never owns the recorder queue.
private final class SpeechCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var failure: String?
    private var watchdog: Task<Void, Never>?
    var isComplete: Bool { lock.lock(); defer { lock.unlock() }; return completed }
    var failureMessage: String? { lock.lock(); defer { lock.unlock() }; return failure }
    func recordFailure(_ message: String) { lock.lock(); failure = message; lock.unlock() }
    func installWatchdog(_ task: Task<Void, Never>) {
        lock.lock(); let finished = completed; if !finished { watchdog = task }; lock.unlock()
        if finished { task.cancel() }
    }
    func finish() {
        lock.lock(); completed = true; let timer = watchdog; watchdog = nil; lock.unlock()
        timer?.cancel()
    }
}

final class LiveSpeechSession: RecognitionSession, @unchecked Sendable {
    private let completion = SpeechCompletion()
    var recordingID: UUID { ticket.recordingID }
    var isComplete: Bool { completion.isComplete }
    private let continuation: AsyncStream<Data>.Continuation
    private let task: Task<Void, Never>
    private let ticket: RecognitionTicket
    private let store: SaytileStore
    private let event: @Sendable (SpeechTimingEvent) -> Void
    private let started = ProcessInfo.processInfo.systemUptime
    init(store: SaytileStore, ticket: RecognitionTicket, review: LocalTextReview? = nil, event: @escaping @Sendable (SpeechTimingEvent) -> Void = { _ in }) {
        self.store = store; self.ticket = ticket; self.event = event
        let began = started
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(300))
        self.continuation = continuation
        let completion = completion
        self.task = Task {
            defer { completion.finish() }
            do { try await Self.recognize(stream: stream, store: store, ticket: ticket, started: began, review: review, event: event) }
            catch { try? await store.failRecognition(ticket: ticket, message: completion.failureMessage ?? error.localizedDescription) }
        }
    }
    func append(_ data: Data) {
        if case .dropped = continuation.yield(data) {
            completion.recordFailure("识别处理跟不上，原音已保留，可稍后重新识别")
            continuation.finish(); task.cancel()
        }
    }
    func finish() {
        continuation.finish()
        event(.init(kind: "inputFinished", elapsedSeconds: ProcessInfo.processInfo.systemUptime - started))
        let active = task
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            active.cancel()
        }
        completion.installWatchdog(watchdog)
    }
    func cancel() { continuation.finish(); task.cancel() }
    func wait() async { await task.value }
    private static func recognize(stream: AsyncStream<Data>, store: SaytileStore, ticket: RecognitionTicket, started: Double, review: LocalTextReview?, event: @escaping @Sendable (SpeechTimingEvent) -> Void) async throws {
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
        let ingress = LocalCandidateIngress(store: store, ticket: ticket, review: review)
        let resultTask = Task {
            var accumulator = SpeechResultAccumulator()
            var audioEnd = 0.0
            var hasText = false
            var lastStable = ""
            var lastDisplayed = ""
            var firstResult = true
            var lastPreview = ""
            for try await result in transcriber.results {
                let snapshot = accumulator.apply(start:result.range.start.seconds, end:CMTimeRangeGetEnd(result.range).seconds, text:String(result.text.characters), isFinal:result.isFinal, finalizedThrough: result.resultsFinalizationTime.seconds)
                audioEnd = max(audioEnd, CMTimeRangeGetEnd(result.range).seconds)
                if !snapshot.fullText.isEmpty {
                    try await ingress.receive(.init(text: snapshot.fullText, stableUTF16Length: snapshot.stableText.utf16.count,
                        audioEndSeconds: audioEnd, timingGranularity: "utterance",
                        isComplete: false))
                }
                if !snapshot.fullText.isEmpty, lastPreview != snapshot.fullText {
                    lastPreview = snapshot.fullText
                    event(.init(kind: "preview", elapsedSeconds: ProcessInfo.processInfo.systemUptime - started, text: lastPreview))
                }
                if firstResult && !snapshot.fullText.isEmpty {
                    firstResult = false
                    event(.init(kind: "firstText", elapsedSeconds: ProcessInfo.processInfo.systemUptime - started))
                }
                if !snapshot.stableText.isEmpty && snapshot.stableText != lastStable {
                    lastStable = snapshot.stableText
                    lastDisplayed = snapshot.stableText
                    hasText = true
                    event(.init(kind: "stableText", elapsedSeconds: ProcessInfo.processInfo.systemUptime - started))
                }
                if !snapshot.fullText.isEmpty && snapshot.fullText != lastDisplayed {
                    lastDisplayed = snapshot.fullText
                    hasText = true
                }
            }
            if !hasText { throw AudioFailure.message("未识别到文字；原音可回听或重试") }
            guard accumulator.snapshot.isCompletelyFinal else { throw AudioFailure.message("部分文字尚未定稿，已保留文字和原音，可稍后重新识别") }
            try await ingress.receive(.init(text: accumulator.snapshot.fullText,
                stableUTF16Length: accumulator.snapshot.stableText.utf16.count,
                audioEndSeconds: audioEnd, timingGranularity: "utterance", isComplete: true))
            try await ingress.finish()
            event(.init(kind: "completed", elapsedSeconds: ProcessInfo.processInfo.systemUptime - started))
        }
        try await withTaskCancellationHandler {
        do {
            try await analyzer.prepareToAnalyze(in: format)
            event(.init(kind: "prepared", elapsedSeconds: ProcessInfo.processInfo.systemUptime - started))
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
            // Finish the resampler too. Closing the AsyncStream without draining
            // the converter drops its filter tail, particularly on short utterances.
            while true {
                guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else { break }
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { _, state in state.pointee = .endOfStream; return nil }
                if status == .error { throw error ?? AudioFailure.message("识别尾部音频转换失败") as NSError }
                if output.frameLength > 0, case .dropped = inputContinuation.yield(AnalyzerInput(buffer: output)) { throw AudioFailure.message("识别队列未能保存尾部；原音可重新识别") }
                if output.frameLength == 0 || status == .endOfStream { break }
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
