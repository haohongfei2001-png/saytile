import Darwin
import Foundation

/// One captured choice per ticket. Capture always owns the PCM journal.
protocol LocalASRProvider: Sendable {
    func open(store: SaytileStore, ticket: RecognitionTicket) -> any RecognitionSession
}
struct AppleLocalASR: LocalASRProvider {
    var review: LocalTextReview? = nil
    func open(store: SaytileStore, ticket: RecognitionTicket) -> any RecognitionSession {
        LiveSpeechSession(store: store, ticket: ticket, review: review)
    }
}
struct NativeLocalASR: LocalASRProvider {
    let model: LocalASRID
    let service: LocalASRService
    var review: LocalTextReview? = nil
    func open(store: SaytileStore, ticket: RecognitionTicket) -> any RecognitionSession {
        ModelRecognitionSession(model: model, service: service, store: store, ticket: ticket, review: review)
    }
}

struct WorkerEvent: Decodable, Sendable {
    let kind: String
    let text: String
    let frames: Int
}

final class ModelWorker: @unchecked Sendable {
    let id: LocalASRID
    let process = Process()
    let input: FileHandle
    let events: AsyncThrowingStream<WorkerEvent, Error>
    init(id: LocalASRID, directory: URL, helpers: URL, stride: Int) throws {
        self.id = id
        let stdin = Pipe(), stdout = Pipe()
        input = stdin.fileHandleForWriting
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.executableURL = helpers.appending(path: id == .sherpa ? "SaytileSherpa" : "SaytileModelWorker")
        if let resources = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resources.appending(path: "default.metallib").path) {
            process.currentDirectoryURL = resources
        }
        process.arguments = [id.rawValue, directory.path, String(stride)]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let (stream, channel) = AsyncThrowingStream<WorkerEvent, Error>.makeStream(bufferingPolicy: .bufferingOldest(128))
        events = stream
        try process.run()
        try? stdin.fileHandleForReading.close()
        try? stdout.fileHandleForWriting.close()
        let source = stdout.fileHandleForReading
        DispatchQueue(label: "saytile.asr.results", qos: .userInitiated).async {
            defer { try? source.close() }
            do {
                var pending = Data()
                // Darwin FileHandle.read(upToCount:) can wait to fill the requested
                // length on a live pipe. A short POSIX read surfaces each flushed line.
                var buffer = [UInt8](repeating: 0, count: 16_384)
                while true {
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(source.fileDescriptor, $0.baseAddress, $0.count) }
                    if count < 0 && errno == EINTR { continue }
                    if count < 0 { throw POSIXError(.EIO) }
                    if count == 0 { break }
                    pending.append(contentsOf: buffer.prefix(count))
                    while let end = pending.firstIndex(of: 10) {
                        let line = pending[..<end]
                        let event = try JSONDecoder().decode(WorkerEvent.self, from: line)
                        if case .dropped = channel.yield(event) { throw AudioFailure.message("本机识别回传队列已满") }
                        pending.removeSubrange(...end)
                    }
                    if pending.count > 1024 * 1024 { throw AudioFailure.message("本机识别输出过长") }
                }
                channel.finish(throwing: AudioFailure.message("本机识别进程已退出"))
            } catch { channel.finish(throwing: error) }
        }
    }
    func write(_ data: Data) throws {
        for start in Swift.stride(from: 0, to: max(1, data.count), by: 65_536) {
            let end = min(start + 65_536, data.count)
            var count = UInt32(end - start).littleEndian
            var frame = withUnsafeBytes(of: &count) { Data($0) }
            frame.append(data[(data.startIndex + start)..<(data.startIndex + end)])
            try input.write(contentsOf: frame)
        }
    }
    func stop() {
        if process.isRunning { process.terminate() }
    }
    deinit { stop(); try? input.close() }
}

public actor LocalASRService {
    public nonisolated let library: LocalModelLibrary
    private let helpers: URL
    private let stride: Int
    private var waiting: [UUID] = []
    private var busy = false
    private var worker: ModelWorker?
    private var idle: Task<Void, Never>?
    public init(root: URL, helpers: URL? = nil, chunkFrames: Int = 19_200) {
        library = LocalModelLibrary(root: root)
        self.helpers = helpers ?? Bundle.main.bundleURL.appending(path: "Contents/Helpers")
        self.stride = chunkFrames
    }
    public func releaseIdle() {
        guard !busy else { return }
        idle?.cancel()
        worker?.stop()
        worker = nil
    }
    public func delete(_ model: LocalASRID) async throws {
        if worker?.id == model {
            guard !busy else { throw AudioFailure.message("本段识别结束后可删除模型") }
            releaseIdle()
        }
        try await library.delete(model)
    }
    func availability(_ id: LocalASRID) async -> SpeechAvailability {
        if id == .apple { return await AppleSpeechService.availability() }
        let status = await library.status(id)
        let ready = status.installed && FileManager.default.isExecutableFile(atPath:
            helpers.appending(path: id == .sherpa ? "SaytileSherpa" : "SaytileModelWorker").path)
        return .init(supported: true, installed: ready, message: ready ? id.title : "\(id.title) · 需要准备模型")
    }
    fileprivate func recognize(_ id: LocalASRID, audio: AsyncStream<Data>, ingress: LocalCandidateIngress) async throws {
        let token = UUID()
        guard waiting.count < 8 else { throw AudioFailure.message("前段识别仍在进行，原音可重新识别") }
        waiting.append(token)
        defer { waiting.removeAll { $0 == token } }
        while busy || waiting.first != token { try await Task.sleep(for: .milliseconds(20)) }
        try Task.checkCancellation()
        busy = true
        idle?.cancel()
        defer {
            busy = false
            idle = Task { do { try await Task.sleep(for: .seconds(30)) } catch { return }; releaseIdle() }
        }
        do {
            let manifest = try LocalModelManifest.load(id)
            let directory = try await library.validated(manifest)
            let fresh = worker?.id != id || worker?.process.isRunning != true
            if fresh {
                worker?.stop()
                worker = try ModelWorker(id: id, directory: directory, helpers: helpers, stride: stride)
            }
            guard let current = worker else { throw ProviderFailure.connection }
            try await withTaskCancellationHandler {
                let sender = Task.detached {
                    for await frame in audio {
                        try Task.checkCancellation()
                        if !frame.isEmpty { try current.write(frame) }
                    }
                    try Task.checkCancellation()
                    try current.write(Data())
                }
                defer { sender.cancel() }
                do {
                    var ready = !fresh, lastFrames = 0
                    var liveText = LocalLiveText(model: id)
                    for try await event in current.events {
                        try Task.checkCancellation()
                        if event.kind == "ready" && !ready { ready = true; continue }
                        guard ready, ["partial", "final"].contains(event.kind), event.frames >= lastFrames else {
                            throw AudioFailure.message("本机识别事件顺序异常")
                        }
                        lastFrames = event.frames
                        let final = event.kind == "final"
                        if !event.text.isEmpty, let stable = liveText.accept(event.text, final: final) {
                            try await ingress.receive(.init(text: event.text, stableUTF16Length: stable,
                                audioEndSeconds: Double(event.frames) / 16_000, timingGranularity: "utterance", isComplete: final))
                        }
                        if final {
                            try await sender.value
                            guard !event.text.isEmpty else { throw ProviderFailure.incomplete }
                            return
                        }
                    }
                    throw ProviderFailure.incomplete
                } catch { current.stop(); throw error }
            } onCancel: { current.stop() }
        } catch { worker?.stop(); worker = nil; throw error }
    }
}

/// A rolling batch decoder can replace a large prefix on a transient pass.
/// Keep that pass off the panel until supported by a later hypothesis. The
/// accepted text always comes verbatim from this model. Only the cache-aware
/// Nemotron decoder appends irrevocable token IDs during a stream.
struct LocalLiveText {
    let model: LocalASRID
    private(set) var previous = ""
    private var readingPrefix = ""
    private var withheld: String?
    init(model: LocalASRID) { self.model = model }
    mutating func accept(_ text: String, final: Bool) -> Int? {
        if final { return text.utf16.count }
        let common = RecognitionUTF16.commonPrefix([previous, text])
        if model == .qwen {
            if !RecognitionUTF16.hasExactPrefix(text, prefix: readingPrefix) {
                // A decoder may permanently change “二十九岁” to “29岁”. Suppressing
                // every later hypothesis would freeze the preview until end of speech.
                // Reconsider only the last 24 visible graphemes, on two consecutive
                // concordant model passes with an unchanged lexical anchor. Never
                // splice text or turn this tentative reading into dispatch evidence.
                let prior = withheld
                withheld = text
                guard let prior else { return nil }
                let supported = RecognitionUTF16.commonPrefix([prior, text])
                let unchanged = common.count
                guard previous.count - unchanged <= 24, text.count >= previous.count,
                      supported.count >= max(unchanged + 4, min(previous.count, 12)) else { return nil }
                let oldTail = Array(previous.dropFirst(unchanged).prefix(24))
                let newTail = String(supported.dropFirst(unchanged).prefix(48))
                guard oldTail.count >= 4, (0...(oldTail.count - 4)).contains(where: { i in
                    let anchor = oldTail[i..<(i + 4)]
                    return anchor.allSatisfy { $0.isLetter || $0.isNumber } && newTail.contains(String(anchor))
                }) else { return nil }
                readingPrefix = String(supported.dropLast(8))
            } else if common.count > 8 {
                let supported = String(common.dropLast(8))
                if supported.utf16.count > readingPrefix.utf16.count { readingPrefix = supported }
            }
            withheld = nil
        }
        previous = text
        return model == .nemotron ? String(common.dropLast()).utf16.count : 0
    }
}

private final class ModelRecognitionSession: RecognitionSession, @unchecked Sendable {
    let recordingID: UUID
    private let state = RecognitionSessionCompletion()
    private let channel: AsyncStream<Data>.Continuation
    private let task: Task<Void, Never>
    private let timeout: Duration
    var isComplete: Bool { state.isComplete }
    init(model: LocalASRID, service: LocalASRService, store: SaytileStore, ticket: RecognitionTicket, review: LocalTextReview?) {
        recordingID = ticket.recordingID
        timeout = model.capability == .batch ? .seconds(180) : .seconds(60)
        let (audio, sender) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(600))
        channel = sender
        let state = state
        task = Task {
            defer { state.finish() }
            let ingress = LocalCandidateIngress(store: store, ticket: ticket, model: model, review: review)
            do {
                try await service.recognize(model, audio: audio, ingress: ingress)
                try await ingress.finish()
            }
            catch {
                try? await store.failRecognition(ticket: ticket, message: "本机识别未完成，原音可重试。\(error.localizedDescription)")
            }
        }
    }
    func append(_ data: Data) { if case .dropped = channel.yield(data) { cancel() } }
    func finish() {
        channel.finish()
        let active = task, deadline = timeout
        state.watch(Task { do { try await Task.sleep(for: deadline) } catch { return }; active.cancel() })
    }
    func cancel() { channel.finish(); task.cancel() }
    func wait() async { await task.value }
}
