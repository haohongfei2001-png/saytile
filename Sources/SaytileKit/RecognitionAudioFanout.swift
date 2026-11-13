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
        fileprivate let local: LocalFailoverDependencies
        fileprivate let liveLocal: LocalFailoverDependencies
        fileprivate let archive: LocalFailoverDependencies
        let route: HostedRoute
        var isHosted: Bool { route != .byok }
        let configuration: RecognitionConfiguration
        let appliedConfiguration: RecognitionConfiguration
        fileprivate let epoch: RecognitionFailoverEpoch
        fileprivate let generation: UInt64
        /// Restrict this exact settings generation without observing newer cloud consent.
        var localOnly: Self {
            var restricted = configuration
            restricted.cloudEnabled = false
            return Self(local: local, liveLocal: local, archive: archive, route: route, configuration: restricted, appliedConfiguration: appliedConfiguration, epoch: epoch, generation: generation)
        }
    }
    private let lock = NSLock()
    private var route = HostedRoute.byok
    private var checkedStreamingID: UUID?
    private var value: RecognitionConfiguration
    private var generation: UInt64 = 0
    private var active = 0
    private let dependencies: RecognitionPipelineDependencies
    private var liveLocal: LocalFailoverDependencies
    private var archive: LocalFailoverDependencies
    private var local: LocalFailoverDependencies
    private var epoch: RecognitionFailoverEpoch
    init(configuration: RecognitionConfiguration = RecognitionConfiguration(), dependencies: RecognitionPipelineDependencies = .live, local: LocalFailoverDependencies = .live) {
        checkedStreamingID = configuration.cloudEnabled ? (configuration.checkedASRConfigurationID ?? configuration.selectedASRModel?.id) : nil
        value = configuration; self.dependencies = dependencies; self.local = local; self.archive = local; self.liveLocal = local
        epoch = RecognitionFailoverEpoch(now: local.now)
    }
    private func recordingSnapshot() -> Snapshot {
        if route != .byok {
            var config = HostedTransport.configuration
            if case .connected(let access) = route, access.expiry > Date() {} else { config.cloudEnabled = false }
            return Snapshot(local: local, liveLocal: liveLocal, archive: archive, route:route,configuration:config,appliedConfiguration:value,epoch:epoch,generation:generation)
        }
        var frozen = value
        frozen.languagePreference = value.resolvedLanguage
        if checkedStreamingID == nil || frozen.selectedASRModel?.id != checkedStreamingID { frozen.cloudEnabled = false }
        return Snapshot(local: local, liveLocal: liveLocal, archive: archive, route:route,configuration: frozen, appliedConfiguration: value, epoch: epoch, generation: generation)
    }
    var snapshot: Snapshot { lock.withLock { recordingSnapshot() } }
    var configuration: RecognitionConfiguration { lock.withLock { value } }
    var usesCloud: Bool { snapshot.configuration.cloudEnabled }
    var isHosted: Bool { lock.withLock { route != .byok } }
    func select(_ new: HostedRoute, revoke: Bool) {
        lock.withLock {
            guard new != route || revoke else { return }
            retired.removeAll { $0.epoch == nil }
            if revoke {
                epoch.invalidate(); retired.forEach { $0.epoch?.invalidate() }; retired.removeAll(); generation &+= 1
            } else { retired.append(Retired(epoch)) }
            route = new; epoch = RecognitionFailoverEpoch(now:local.now)
        }
    }
    func localAvailability() async -> SpeechAvailability { await snapshot.local.availability() }
    func selectLocal(live: LocalASRID, archive: LocalASRID, service: LocalASRService, review: LocalTextReview? = nil, onUnavailable: (@Sendable (LocalASRID) -> Void)? = nil) {
        lock.withLock {
            self.local = .device(live, service: service)
            self.archive = .device(archive, service: service)
            self.liveLocal = .device(live, service: service, review: review, onUnavailable: onUnavailable)
        }
    }
    private final class Retired {
        weak var epoch: RecognitionFailoverEpoch?
        init(_ epoch: RecognitionFailoverEpoch) { self.epoch = epoch }
    }
    private var retired: [Retired] = []
    func update(_ config: RecognitionConfiguration, nextUtteranceOnly: Bool = false) {
        lock.withLock {
            // Fence old work before a caller can observe/admit the new snapshot.
            retired.removeAll { $0.epoch == nil }
            if nextUtteranceOnly {
                retired.append(Retired(epoch))
            } else {
                epoch.invalidate()
                retired.forEach { $0.epoch?.invalidate() }
                retired.removeAll()
                generation &+= 1
            }
            checkedStreamingID = config.cloudEnabled ? (config.checkedASRConfigurationID ?? config.selectedASRModel?.id) : nil
            value = config
            epoch = RecognitionFailoverEpoch(now: local.now)
        }
    }
    func make(store: SaytileStore, ticket: RecognitionTicket, snapshot requested: Snapshot? = nil, archived: Bool = false, newCapture: Bool = false) -> any RecognitionSession {
        // Ticket creation awaits Store. A settings/revocation change in that gap
        // must not mix generations or revive a cancelled cloud configuration.
        lock.withLock {
            let accepted = requested ?? recordingSnapshot()
            guard accepted.generation == generation else {
                return DeferredRecognitionSession(store: store, ticket: ticket,
                    message: "识别设置已更新，本段原音继续保存，等待使用新设置恢复。")
            }
            let config = accepted.configuration
            guard config.cloudEnabled else { return (newCapture ? accepted.liveLocal : archived ? accepted.archive : accepted.local).make(store, ticket) }
            guard active < 8 else { return DeferredRecognitionSession(store: store, ticket: ticket) }
            active += 1
            let (cloud, probe) = accepted.epoch.admitCloud()
            var transport = dependencies
            if case .connected(let access) = accepted.route { transport = HostedTransport(access,ticket).dependencies }
            return FailoverRecognitionSession(store: store, ticket: ticket, configuration: config,
                dependencies: transport, local: accepted.local, epoch: accepted.epoch, cloud: cloud, probe: probe) { [weak self] in
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
