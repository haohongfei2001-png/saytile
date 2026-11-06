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
    private var frames: Int64 = 0
    private let onOverflow: @Sendable (UUID) -> Void
    init(ids: [UUID], queueFrames: Int = 300,
         onOverflow: @escaping @Sendable (UUID) -> Void = { _ in }) {
        var channels: [Channel] = []
        for id in ids {
            let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(max(1, queueFrames)))
            channels.append(.init(id: id, audio: stream)); continuations[id] = continuation
        }
        self.channels = channels; self.onOverflow = onOverflow
    }
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        var overflow: [UUID] = []
        lock.withLock {
            guard !closed else { return }
            frames += Int64(data.count / 2)
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
    var isFinished: Bool { lock.withLock { closed } }
    var duration: Double { lock.withLock { Double(frames) / 16_000 } }

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
    struct Snapshot: Sendable {
        let configuration: RecognitionConfiguration
        fileprivate let generation: UInt64
    }
    private let lock = NSLock()
    private var value: RecognitionConfiguration
    private var generation: UInt64 = 0
    private var active = 0
    private let dependencies: RecognitionPipelineDependencies
    private let local: LocalFailoverDependencies
    private var epoch: RecognitionFailoverEpoch
    init(configuration: RecognitionConfiguration = RecognitionConfiguration(), dependencies: RecognitionPipelineDependencies = .live, local: LocalFailoverDependencies = .live) {
        value = configuration; self.dependencies = dependencies; self.local = local
        epoch = RecognitionFailoverEpoch(now: local.now)
    }
    var snapshot: Snapshot { lock.withLock { Snapshot(configuration: value, generation: generation) } }
    var configuration: RecognitionConfiguration { snapshot.configuration }
    var usesCloud: Bool { configuration.cloudEnabled }
    func update(_ config: RecognitionConfiguration) {
        lock.withLock {
            // Fence old work before a caller can observe/admit the new snapshot.
            epoch.invalidate()
            value = config; generation &+= 1
            epoch = RecognitionFailoverEpoch(now: local.now)
        }
    }
    func make(store: SaytileStore, ticket: RecognitionTicket, snapshot requested: Snapshot? = nil) -> any RecognitionSession {
        // Ticket creation awaits Store. A settings/revocation change in that gap
        // must not mix generations or revive a cancelled cloud configuration.
        lock.withLock {
            let accepted = requested ?? Snapshot(configuration: value, generation: generation)
            guard accepted.generation == generation else {
                return DeferredRecognitionSession(store: store, ticket: ticket,
                    message: "识别设置已更新，本段原音继续保存，等待使用新设置恢复。")
            }
            let config = accepted.configuration
            guard config.cloudEnabled else { return LiveSpeechSession(store: store, ticket: ticket) }
            guard active < 8 else { return DeferredRecognitionSession(store: store, ticket: ticket) }
            active += 1
            let (cloud, probe) = epoch.admitCloud()
            return FailoverRecognitionSession(store: store, ticket: ticket, configuration: config,
                dependencies: dependencies, local: local, epoch: epoch, cloud: cloud, probe: probe) { [weak self] in
                self?.lock.withLock { self?.active -= 1 }
            }
        }
    }
}

private final class DeferredRecognitionSession: RecognitionSession, @unchecked Sendable {
    let recordingID: UUID
    private let completion = RecognitionSessionCompletion()
    private let task: Task<Void, Never>
    var isComplete: Bool { completion.isComplete }
    init(store: SaytileStore, ticket: RecognitionTicket, message: String = "先前模型仍在复核，本段原音已保留并等待恢复。") {
        recordingID = ticket.recordingID
        let completion = completion
        task = Task {
            try? await store.failRecognition(ticket: ticket, message: message)
            completion.finish()
        }
    }
    func append(_ data: Data) {}
    func finish() {}
    func cancel() { task.cancel() }
    func wait() async { await task.value }
}
