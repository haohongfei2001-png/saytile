import Foundation

/// One immutable PCM block is offered to every model after the journal accepts it.
/// Queues are independent: overflow closes only the affected model's stream and is
/// surfaced as failure, never treated as a successful but shorter transcript.
final class RecognitionAudioFanout: @unchecked Sendable {
    struct Channel: Sendable { let id: UUID; let audio: AsyncStream<Data> }
    let channels: [Channel]
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Data>.Continuation] = [:]
    private var closed = false
    private var failed: Set<UUID> = []
    private var pcm = Data()
    private var frames: Int64 = 0
    private var retainedWholeAudio = true
    private let maximumReviewBytes: Int
    private let onOverflow: @Sendable (UUID) -> Void
    init(ids: [UUID], queueFrames: Int = 300, maximumReviewBytes: Int = 12_000_000,
         onOverflow: @escaping @Sendable (UUID) -> Void = { _ in }) {
        var channels: [Channel] = []
        for id in ids {
            let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(max(1, queueFrames)))
            channels.append(.init(id: id, audio: stream)); continuations[id] = continuation
        }
        self.channels = channels; self.maximumReviewBytes = maximumReviewBytes; self.onOverflow = onOverflow
    }
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        var overflow: [UUID] = []
        lock.withLock {
            guard !closed else { return }
            frames += Int64(data.count / 2)
            if retainedWholeAudio && pcm.count + data.count <= maximumReviewBytes { pcm.append(data) }
            else { retainedWholeAudio = false; pcm.removeAll(keepingCapacity: false) }
            for (id, continuation) in continuations where !failed.contains(id) {
                if case .dropped = continuation.yield(data) {
                    failed.insert(id); continuation.finish(); overflow.append(id)
                }
            }
        }
        overflow.forEach(onOverflow)
    }
    func finish() {
        lock.withLock {
            guard !closed else { return }; closed = true
            continuations.values.forEach { $0.finish() }
        }
    }
    func didOverflow(_ id: UUID) -> Bool { lock.withLock { failed.contains(id) } }
    var duration: Double { lock.withLock { Double(frames) / 16_000 } }
    var snapshot: Data? { lock.withLock { retainedWholeAudio ? pcm : nil } }
    /// Taking a bounded, exact sample interval never interpolates a word timestamp.
    func clip(start: Double, end: Double) -> Data? {
        lock.withLock {
            guard retainedWholeAudio, start.isFinite, end.isFinite, start >= 0, end > start else { return nil }
            let a = Int((start * 16_000).rounded(.down)) * 2
            let b = min(pcm.count, Int((end * 16_000).rounded(.up)) * 2)
            guard a >= 0, b > a, a < pcm.count else { return nil }
            return pcm.subdata(in: a..<b)
        }
    }
}

final class RecognitionSessionCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var watchdog: Task<Void, Never>?
    var isComplete: Bool { lock.withLock { done } }
    func finish() {
        let timer = lock.withLock { done = true; let timer = watchdog; watchdog = nil; return timer }
        timer?.cancel()
    }
    func watch(_ task: Task<Void, Never>) {
        let isDone = lock.withLock { if !done { watchdog = task }; return done }
        if isDone { task.cancel() }
    }
}

/// A shared factory bounds in-flight logical jobs independently from the number of
/// experts. Capacity exhaustion queues the saved recording instead of cancelling
/// an older accepted job or stopping capture.
final class RecognitionSessionFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var value: RecognitionConfiguration
    private var active = 0
    init(configuration: RecognitionConfiguration = RecognitionConfiguration()) { value = configuration }
    var configuration: RecognitionConfiguration { lock.withLock { value } }
    var usesCloud: Bool { configuration.cloudEnabled }
    func update(_ config: RecognitionConfiguration) { lock.withLock { value = config } }
    func make(store: SaytileStore, ticket: RecognitionTicket) -> any RecognitionSession {
        let config = configuration
        guard config.cloudEnabled else { return LiveSpeechSession(store: store, ticket: ticket) }
        let admitted = lock.withLock { if active >= 8 { return false }; active += 1; return true }
        guard admitted else { return DeferredRecognitionSession(store: store, ticket: ticket) }
        return MultiRecognitionSession(store: store, ticket: ticket, configuration: config) { [weak self] in
            self?.lock.withLock { self?.active -= 1 }
        }
    }
}

private final class DeferredRecognitionSession: RecognitionSession, @unchecked Sendable {
    let recordingID: UUID
    private let completion = RecognitionSessionCompletion()
    private let task: Task<Void, Never>
    var isComplete: Bool { completion.isComplete }
    init(store: SaytileStore, ticket: RecognitionTicket) {
        recordingID = ticket.recordingID
        let completion = completion
        task = Task {
            try? await store.failRecognition(ticket: ticket, message: "先前模型仍在复核，本段原音已保留并等待恢复。")
            completion.finish()
        }
    }
    func append(_ data: Data) {}
    func finish() {}
    func cancel() { task.cancel() }
    func wait() async { await task.value }
}
