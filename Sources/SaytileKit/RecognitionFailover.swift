import Foundation

private extension ProviderFailure {
    var canTriggerLocalFailover: Bool {
        if !canRetryAutomatically { return true }
        switch self {
        case .connection, .rateLimited: return true
        default: return false
        }
    }
}

/// Runtime-only routing. Never writes cloudEnabled, consent, credentials or preferences.
/// One next-segment probe after each backoff; three failed probes exhaust this generation.
final class RecognitionFailoverEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    private var failures = 0
    private var retryAt = Date.distantPast
    private var probe: UUID?
    private var blocked = false
    private var owners: [UUID: RecognitionFailoverOwner] = [:]
    let now: @Sendable () -> Date
    init(now: @escaping @Sendable () -> Date) { self.now = now }
    func check() throws { try Task.checkCancellation(); if !lock.withLock({ valid }) { throw CancellationError() } }
    func admitCloud() -> (Bool, UUID?) {
        lock.withLock {
            guard valid, !blocked else { return (false, nil) }
            if failures == 0 { return (true, nil) }
            guard failures <= 3, probe == nil, now() >= retryAt else { return (false, nil) }
            let id = UUID(); probe = id; return (true, id)
        }
    }
    func failed(_ failure: ProviderFailure, probe id: UUID?) {
        lock.withLock {
            guard valid else { return }
            if !failure.canRetryAutomatically {
                blocked = true
            } else if failure.canTriggerLocalFailover {
                // Coalesce failures from concurrent pre-outage sessions.
                if failures == 0 || (id != nil && id == probe) {
                    failures += 1
                    retryAt = now().addingTimeInterval(max(failure.minimumRetryDelay,
                        [5.0, 15, 60, 60][min(failures - 1, 3)]))
                }
                // A concurrent rate limit must never shorten an existing circuit delay.
                retryAt = max(retryAt, now().addingTimeInterval(failure.minimumRetryDelay))
            } else {
                return
            }
            if id == probe { probe = nil }
        }
    }
    func ended(probe id: UUID?, succeeded: Bool) {
        lock.withLock {
            guard let id, id == probe else { return }
            probe = nil
            if succeeded { failures = 0; retryAt = .distantPast }
            else { retryAt = now().addingTimeInterval(60); failures += 1 }
        }
    }
    func register(_ owner: RecognitionFailoverOwner, id: UUID) {
        let reject = lock.withLock { if valid { owners[id] = owner }; return !valid }
        if reject { owner.cancel() }
    }
    func remove(_ id: UUID) { _ = lock.withLock { owners.removeValue(forKey: id) } }
    func invalidate() {
        let old = lock.withLock { valid = false; let old = Array(owners.values); owners.removeAll(); return old }
        old.forEach { $0.cancel() }
    }
}

/// Owns every child across suspension points, including the cloud-to-local handover.
final class RecognitionFailoverOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var child: (any RecognitionSession)?
    private var task: Task<Void, Never>?
    private var cancelled = false
    private var closed = false
    private var forwarding = true
    var inputClosed: Bool { lock.withLock { closed } }
    var current: (any RecognitionSession)? { lock.withLock { child } }
    func installTask(_ value: Task<Void, Never>) {
        let reject = lock.withLock { task = value; return cancelled }
        if reject { value.cancel() }
    }
    func install(_ value: any RecognitionSession, live: Bool) throws {
        try lock.withLock {
            guard !cancelled else { value.cancel(); throw CancellationError() }
            child = value; forwarding = live
            if closed && live { value.finish() }
        }
    }
    func detach() -> (any RecognitionSession)? {
        lock.withLock { let old = child; child = nil; forwarding = false; return old }
    }
    func append(_ data: Data) { lock.withLock { if !cancelled && !closed && forwarding { child?.append(data) } } }
    func finish() { lock.withLock { closed = true; if forwarding { child?.finish() } } }
    func cancel() {
        let values = lock.withLock { cancelled = true; return (child, task) }
        values.0?.cancel(); values.1?.cancel()
    }
}

struct LocalFailoverDependencies: Sendable {
    var availability: @Sendable () async -> SpeechAvailability
    var make: @Sendable (SaytileStore, RecognitionTicket) -> any RecognitionSession
    var now: @Sendable () -> Date = { Date() }
    static let live = Self(availability: { await AppleSpeechService.availability() },
                           make: { AppleLocalASR().open(store: $0, ticket: $1) })
    static func device(_ id: LocalASRID, service: LocalASRService, review: LocalTextReview? = nil, onUnavailable: (@Sendable (LocalASRID) -> Void)? = nil) -> Self {
        if id == .apple { return Self(availability: { await AppleSpeechService.availability() }, make: { AppleLocalASR(onUnavailable: onUnavailable, review: review).open(store: $0, ticket: $1) }) }
        return Self(availability: { await service.availability(id) }, make: { NativeLocalASR(onUnavailable: onUnavailable, model: id, service: service, review: review).open(store: $0, ticket: $1) })
    }
}

private struct FailureObservedProvider: StreamingASRProvider {
    let base: any StreamingASRProvider
    let epoch: RecognitionFailoverEpoch
    let report: @Sendable (Error) -> Void
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        do {
            try epoch.check()
            try await base.run(audio: audio, configuration: configuration, credential: credential) { event in
                try epoch.check(); try Task.checkCancellation(); try await emit(event)
            }
        } catch { report(error); throw error }
    }
}

/// A single publication owner. Cloud sees live full PCM; after failure Apple sees
/// only exact journal ranges, including newly checkpointed tail, on a NEW ticket.
final class FailoverRecognitionSession: RecognitionSession, @unchecked Sendable {
    let recordingID: UUID
    private let owner: RecognitionFailoverOwner
    private let completion = RecognitionSessionCompletion()
    private let task: Task<Void, Never>
    var isComplete: Bool { completion.isComplete }
    private enum Event: Sendable { case failure(ProviderFailure), ended }
    init(store: SaytileStore, ticket: RecognitionTicket, configuration: RecognitionConfiguration,
         dependencies: RecognitionPipelineDependencies, local: LocalFailoverDependencies,
         epoch: RecognitionFailoverEpoch, cloud: Bool, probe: UUID?,
         onComplete: @escaping @Sendable () -> Void) {
        recordingID = ticket.recordingID
        let owner = RecognitionFailoverOwner(); self.owner = owner
        let id = UUID(), completion = completion
        let (events, signal) = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingOldest(8))
        let report: @Sendable (Error) -> Void = { error in
            guard !Task.isCancelled else { return }
            let failure: ProviderFailure
            if let value = error as? ProviderFailure { failure = value }
            else if let value = error as? URLError, value.code != .cancelled { failure = .connection }
            else { return }
            if failure.canTriggerLocalFailover {
                signal.yield(.failure(failure))
            }
            // Cancellation and missing finals do not justify restarting recognition.
        }
        var scoped = dependencies
        scoped.credential = { item in
            do {
                try epoch.check()
                let credential = try dependencies.credential(item)
                // Keychain reads may already be in flight when settings revoke
                // this epoch. Never hand a newly replaced key to old work.
                try epoch.check()
                return credential
            }
            catch { report(error); throw error }
        }
        scoped.streaming = { provider in
            do {
                try epoch.check()
                return FailureObservedProvider(base: try dependencies.streaming(provider), epoch: epoch, report: report)
            } catch { report(error); throw error }
        }
        // GPT is part of the live recognition path too. Observe failures from the
        // persistent Responses client, not only failures while opening ASR streams.
        scoped.arbitrate = { evidence, prefix, context, item, credential in
            do {
                try epoch.check()
                let result = try await dependencies.arbitrate(evidence, prefix, context, item, credential)
                try epoch.check()
                return result
            } catch {
                report(error)
                throw error
            }
        }
        scoped.reviewFailure = report
        // Admission and initial attachment are synchronous: no initial PCM can fall
        // into a Task scheduling gap. Subsequent local input comes from disk only.
        let canSelectCloudASR = configuration.selectedASRModel != nil
        let initial: (any RecognitionSession)? = cloud && canSelectCloudASR ? MultiRecognitionSession(store: store, ticket: ticket,
            configuration: configuration, dependencies: scoped) : nil
        if let initial { try? owner.install(initial, live: true) }
        epoch.register(owner, id: id)
        task = Task {
            var currentTicket = ticket
            defer { signal.finish(); epoch.remove(id); completion.finish(); onComplete() }
            do {
                try epoch.check()
                if let cloudSession = owner.current {
                    let waiter = Task { await cloudSession.wait(); signal.yield(.ended) }
                    defer { waiter.cancel() }
                    var failure: ProviderFailure?
                    for await event in events {
                        if case .failure(let reason) = event { failure = reason }
                        break
                    }
                    try epoch.check()
                    if let failure {
                        epoch.failed(failure, probe: probe)
                        // Old callbacks must drain before minting the local generation.
                        let old = owner.detach(); old?.cancel(); await old?.wait()
                        try epoch.check()
                    } else {
                        let record = try await store.recording(id: ticket.recordingID)
                        epoch.ended(probe: probe, succeeded: record?.recognitionState == .completed)
                        _ = owner.detach()
                        return
                    }
                }
                try epoch.check()
                let availability = await local.availability()
                try epoch.check()
                guard availability.supported && availability.installed else {
                    // Queue by recording, since the failed cloud ticket may already be terminal.
                    try await store.queueLocalFailover(recordingID: ticket.recordingID, epoch: epoch)
                    return
                }
                currentTicket = try await store.beginLocalFailover(recordingID: ticket.recordingID, epoch: epoch)
                try epoch.check()
                let session = local.make(store, currentTicket)
                try owner.install(session, live: false)
                var cursor: Int64 = 0
                while !session.isComplete {
                    try epoch.check()
                    // Read close first, then watermark: close is published only after the
                    // final journal synchronization. No nondurable or omitted final tail.
                    let closed = owner.inputClosed
                    let chunks = try await store.audioChunks(recordingID: ticket.recordingID)
                    let durable = chunks.reduce(Int64(0)) { $0 + $1.frames }
                    if cursor < durable {
                        let count = Int(min(1_600, durable - cursor))
                        let data = try await store.readPCMRange(ticket: currentTicket, startFrame: cursor, frameCount: count)
                        try epoch.check()
                        session.append(data); cursor += Int64(count)
                    } else if closed {
                        session.finish(); await session.wait(); break
                    }
                    // At most one 100ms PCM block per 50ms: bounded memory and up to
                    // 2x catch-up. Normal journal checkpoints publish each second of audio;
                    // the shorter remaining tail waits for the next checkpoint or close.
                    try await Task.sleep(for: .milliseconds(50))
                }
                _ = owner.detach()
            } catch {
                let old = owner.detach(); old?.cancel(); await old?.wait()
                epoch.ended(probe: probe, succeeded: false)
                try? await store.failRecognition(ticket: currentTicket,
                    message: error is CancellationError ? "识别设置已更新或识别已取消；原音和候选保留。" : "本地恢复未完成；原音保留在恢复队列。")
            }
        }
        owner.installTask(task)
    }
    func append(_ data: Data) { owner.append(data) }
    func finish() { owner.finish() }
    func cancel() { owner.cancel() }
    func wait() async { await task.value }
}
