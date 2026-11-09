import Foundation
import Testing
@testable import SaytileKit

private final class FailoverClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 100)
    func now() -> Date { lock.withLock { time } }
    func advance(_ seconds: Double) { lock.withLock { time = time.addingTimeInterval(seconds) } }
}
private actor FailoverProbe {
    var failure: ProviderFailure?
    var cloudStarts = 0
    var activeCloud = 0
    var overlap = false
    var localStarts = 0
    var localBytes: [UUID: Data] = [:]
    var cloudBytes: [CloudProvider: Data] = [:]
    var staleEmit: (@Sendable (ProviderTranscriptEvent) async throws -> Void)?
    var availabilityEntered = false
    var holdAvailability = false
    var installed = true
    var supported = true
    func setFailure(_ value: ProviderFailure?) { failure = value }
    func setAvailability(installed: Bool, supported: Bool = true, hold: Bool = false) { self.installed = installed; self.supported = supported; holdAvailability = hold }
    func availability() async -> SpeechAvailability {
        availabilityEntered = true
        while holdAvailability && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(2)) }
        return .init(supported: supported, installed: installed, message: "synthetic availability")
    }
    func startCloud() { cloudStarts += 1; activeCloud += 1 }
    func endCloud() { activeCloud -= 1 }
    func cloud(_ data: Data, provider: CloudProvider, emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) throws {
        cloudBytes[provider, default: Data()].append(data)
        staleEmit = emit
        // One failed provider is enough to lose the dual-expert contract.
        if provider == .qwenMessage, let failure { throw failure }
    }
    func local(_ data: Data, id: UUID) { localBytes[id, default: Data()].append(data) }
    func startLocal() { localStarts += 1; overlap = overlap || activeCloud > 0 }
    func lateCallback() async -> Bool {
        do { try await staleEmit?(.init(text: "stale", stableUTF16Length: 5, audioEndSeconds: 1, isComplete: true)); return false }
        catch { return true }
    }
}
private struct FailoverCloud: StreamingASRProvider {
    let probe: FailoverProbe
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        await probe.startCloud()
        do {
        var bytes = 0
        for await data in audio {
            try Task.checkCancellation()
            try await probe.cloud(data, provider: configuration.provider, emit: emit)
            bytes += data.count
            try await emit(.init(text: "hello", stableUTF16Length: 0, audioEndSeconds: Double(bytes) / 32_000, isComplete: false))
        }
        try Task.checkCancellation()
        try await emit(.init(text: "hello", stableUTF16Length: 5, audioEndSeconds: Double(bytes) / 32_000,
                             timingGranularity: "utterance", isComplete: true))
        } catch { await probe.endCloud(); throw error }
        await probe.endCloud()
    }
}
private final class FailoverLocal: RecognitionSession, @unchecked Sendable {
    let recordingID: UUID
    private let completion = RecognitionSessionCompletion()
    private let input: AsyncStream<Data>.Continuation
    private let task: Task<Void, Never>
    var isComplete: Bool { completion.isComplete }
    init(store: SaytileStore, ticket: RecognitionTicket, probe: FailoverProbe) {
        recordingID = ticket.recordingID
        let (stream, input) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(4))
        self.input = input
        let completion = completion
        task = Task {
            defer { completion.finish() }
            await probe.startLocal()
            let ingress = LocalCandidateIngress(store: store, ticket: ticket)
            do {
                var bytes = 0
                for await data in stream {
                    try Task.checkCancellation()
                    await probe.local(data, id: ticket.id); bytes += data.count
                }
                try Task.checkCancellation()
                try await ingress.receive(.init(text: "hello", stableUTF16Length: 5,
                    audioEndSeconds: Double(bytes) / 32_000, timingGranularity: "utterance", isComplete: true))
                try await ingress.finish()
            } catch { try? await store.failRecognition(ticket: ticket, message: "synthetic local stopped") }
        }
    }
    func append(_ data: Data) { if case .dropped = input.yield(data) { cancel() } }
    func finish() { input.finish() }
    func cancel() { input.finish(); task.cancel() }
    func wait() async { await task.value }
}
private struct OfflineFixture {
    let root: URL
    let store: SaytileStore
    let worker: CaptureWorker
    let factory: RecognitionSessionFactory
    let config: RecognitionConfiguration
    let probe = FailoverProbe()
    let clock = FailoverClock()
    init() throws {
        root = URL(fileURLWithPath: "/tmp/saytile-offline-20261107-fixture-" + UUID().uuidString)
        store = try SaytileStore(directory: root)
        var config = RecognitionConfiguration(); config.languagePreference = .chinese; config.cloudEnabled = true
        for index in config.models.indices {
            config.models[index].cloudConsent = true
            if config.models[index].provider == .qwenMessage { config.models[index].workspaceID = "synthetic" }
        }
        self.config = config
        let probe = probe, clock = clock
        let dependencies = RecognitionPipelineDependencies(credential: { _ in "synthetic-not-a-key" },
            streaming: { _ in FailoverCloud(probe: probe) },
            transcribe: { _, _, _ in throw ProviderFailure.incomplete },
            arbitrate: { evidence, _, _, _, _ in
                guard let source = evidence.first else { throw ProviderFailure.incomplete }
                return (.init(selections: [.init(candidateID: source.candidateID, utf16Start: 0, utf16End: source.text.utf16.count)],
                    unresolved: false, needsAudioReview: false, reasonCode: "synthetic"),
                    .init(requestID: nil, inputTokens: nil, outputTokens: nil, elapsedSeconds: 0))
            }, listen: { _, _, _ in throw ProviderFailure.incomplete })
        let local = LocalFailoverDependencies(availability: { await probe.availability() },
            make: { FailoverLocal(store: $0, ticket: $1, probe: probe) }, now: { clock.now() })
        factory = RecognitionSessionFactory(configuration: config, dependencies: dependencies, local: local)
        worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 32_000), sampleRate: 16_000,
            recognitionFactory: factory, update: { _, _ in }, failed: { _ in Issue.record("Capture must not stop for ASR") })
    }
    func cleanup() async throws {
        await worker.cancelRecognitionAndWait(); try await store.close()
        try FileManager.default.removeItem(at: root)
    }
    func drain() async { for session in await worker.retired { await session.wait() } }
}
private func eventually(_ condition: () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while try await !condition() {
        guard ContinuousClock.now < deadline else { Issue.record("Timed out awaiting synthetic event"); throw ProviderFailure.incomplete }
        try await Task.sleep(for: .milliseconds(5))
    }
}

@Suite("Automatic cloud outage to durable Apple candidate failover")
struct OfflineFailoverTests {
    @Test func liveFailureFollowsDurableTailThenRestoresSelectedCloudOnNextSegment() async throws {
        let f = try OfflineFixture()
        try await f.worker.beginUtterance()
        let id = try #require(await f.worker.recordingID)
        let prefix = Data(repeating: 7, count: 32_000), tail = Data(repeating: 13, count: 32_000)
        try await f.worker.append(prefix)
        try await eventually {
            let starts = await f.probe.cloudStarts, streams = await f.probe.cloudBytes.count
            return starts == 1 && streams == 1
        }
        await f.probe.setFailure(.connection)
        try await f.worker.append(Data(repeating: 9, count: 640)) // nondurable until next checkpoint
        try await eventually { await f.probe.localStarts == 1 }
        #expect(try await f.store.recording(id: id)?.isRecording == true)
        #expect(f.factory.configuration == f.config)
        try await f.worker.append(tail)
        // Before segment close, Apple has caught up to the new durable watermark.
        try await eventually { await f.probe.localBytes.values.first?.count == 64_640 }
        #expect(try await f.store.recording(id: id)?.isRecording == true)
        let finalTail = Data(repeating: 15, count: 640)
        try await f.worker.append(finalTail)
        try await f.worker.endUtterance(); await f.drain()
        let expected = prefix + Data(repeating: 9, count: 640) + tail + finalTail
        #expect(await f.probe.localBytes.values.first == expected)
        #expect(await f.probe.overlap == false)
        var durable = Data()
        for chunk in try await f.store.audioChunks(recordingID: id) {
            durable.append(try Data(contentsOf: await f.store.audioURL(for: chunk)).dropFirst(44))
        }
        #expect(durable == expected)
        #expect(try await f.store.recording(id: id)?.text == "hello")
        #expect(try await f.store.recording(id: id)?.recognitionState == .completed)
        let evidence = try await f.store.recognitionCandidates(recordingID: id)
        #expect(evidence.contains { $0.run.provider == "apple-speech-analyzer" && $0.isComplete })
        #expect(evidence.contains { $0.run.provider != "apple-speech-analyzer" })
        #expect(await f.probe.lateCallback())
        #expect(try await f.store.recording(id: id)?.text == "hello")
        // No restoration retry on this ticket. Only a later segment may probe.
        await f.probe.setFailure(nil); f.clock.advance(6)
        try await f.worker.beginUtterance()
        let next = try #require(await f.worker.recordingID)
        try await f.worker.append(prefix); try await f.worker.endUtterance(); await f.drain()
        #expect(await f.probe.cloudStarts == 2)
        #expect(await f.probe.localStarts == 1)
        #expect(try await f.store.recording(id: next)?.recognitionState == .completed)
        #expect(f.factory.configuration == f.config)
        try await f.cleanup()
    }

    @Test(arguments: [false, true])
    func unavailableAppleQueuesAndNextRecordingIsLocalWithoutAToggle(supported: Bool) async throws {
        let f = try OfflineFixture()
        await f.probe.setFailure(.connection); await f.probe.setAvailability(installed: false, supported: supported)
        try await f.worker.beginUtterance()
        let id = try #require(await f.worker.recordingID)
        try await f.worker.append(Data(repeating: 1, count: 640))
        try await eventually { try await f.store.recording(id: id)?.recognitionState == .queued }
        #expect(try await f.store.recording(id: id)?.isRecording == true)
        try await f.worker.append(Data(repeating: 2, count: 640))
        try await f.worker.endUtterance(); await f.drain()
        #expect(try await f.store.pendingRecordings().contains { $0.id == id })
        #expect(await f.probe.localStarts == 0)
        let cloudBefore = await f.probe.cloudStarts
        await f.probe.setAvailability(installed: true)
        try await f.worker.beginUtterance()
        let next = try #require(await f.worker.recordingID)
        try await f.worker.append(Data(repeating: 3, count: 640)); try await f.worker.endUtterance(); await f.drain()
        #expect(await f.probe.cloudStarts == cloudBefore)
        #expect(await f.probe.localStarts == 1)
        #expect(try await f.store.recording(id: next)?.recognitionState == .completed)
        #expect(f.factory.configuration == f.config)
        try await f.cleanup()
    }

    @Test func revocationDuringAvailabilityFencesHandoverAndDropsOldOwners() async throws {
        let f = try OfflineFixture()
        await f.probe.setFailure(.connection); await f.probe.setAvailability(installed: true, hold: true)
        try await f.worker.beginUtterance()
        let id = try #require(await f.worker.recordingID)
        try await f.worker.append(Data(repeating: 1, count: 640))
        try await eventually { await f.probe.availabilityEntered }
        var revoked = f.config
        for index in revoked.models.indices { revoked.models[index].cloudConsent = false }
        f.factory.update(revoked)
        await f.worker.cancelRecognitionAndWait()
        await f.probe.setAvailability(installed: true)
        #expect(await f.probe.localStarts == 0)
        #expect(await f.probe.lateCallback())
        try await f.worker.endUtterance(); await f.drain()
        let starts = await f.probe.cloudStarts
        f.clock.advance(100)
        try await f.worker.beginUtterance()
        try await f.worker.append(Data(repeating: 2, count: 640)); try await f.worker.endUtterance(); await f.drain()
        #expect(await f.probe.cloudStarts == starts)
        #expect(await f.probe.localStarts == 0)
        #expect(try await f.store.recording(id: id)?.recognitionState != .completed)
        try await f.cleanup()
    }

    @Test(arguments: [DispatchState.confirmed, .unverified])
    func recoveryPreservesExternalReservationWithoutRepeatingStableText(state: DispatchState) async throws {
        let f = try OfflineFixture()
        await f.probe.setFailure(.connection)
        let binding = try await f.store.createBinding(label: "synthetic")
        try await f.worker.beginUtterance()
        let id = try #require(await f.worker.recordingID)
        try await f.worker.append(Data(repeating: 4, count: 640)); try await f.worker.endUtterance(); await f.drain()
        let revision = try #require(await f.store.latestDispatchableRevision(recordingID: id))
        let reservation = try #require(await f.store.reserveDispatch(bindingID: binding, recordingID: id, revisionID: revision.id, stableUTF16End: 5))
        try await f.store.completeDispatch(id: reservation.id, state: state)
        let candidatesBefore = try await f.store.recognitionCandidates(recordingID: id).count
        let ticket = try await f.store.beginFusionRecognition(recordingID: id)
        let session = f.factory.make(store: f.store, ticket: ticket)
        session.finish(); await session.wait()
        #expect(try await f.store.recognitionCandidates(recordingID: id).count > candidatesBefore)
        #expect(try await f.store.fusionReservedPrefix(recordingID: id) == "hello")
        #expect(try await f.store.dispatchState(id: reservation.id) == state)
        let nextRevision = try #require(await f.store.latestDispatchableRevision(recordingID: id))
        #expect(try await f.store.reserveDispatch(bindingID: binding, recordingID: id, revisionID: nextRevision.id, stableUTF16End: 5) == nil)
        try await f.cleanup()
    }

    @Test(arguments: [ProviderFailure.authorization, .permission, .regionMismatch, .quota,
                      .configuration("synthetic"), .protocolViolation("synthetic")])
    func nonNetworkFailureStopsAutomaticCloudAttempts(reason: ProviderFailure) async throws {
        let f = try OfflineFixture()
        await f.probe.setFailure(reason)
        try await f.worker.beginUtterance()
        try await f.worker.append(Data(repeating: 8, count: 640)); try await f.worker.endUtterance(); await f.drain()
        let starts = await f.probe.cloudStarts
        f.clock.advance(100_000)
        try await f.worker.beginUtterance()
        let id = try #require(await f.worker.recordingID)
        try await f.worker.append(Data(repeating: 9, count: 640)); try await f.worker.endUtterance(); await f.drain()
        #expect(await f.probe.cloudStarts == starts)
        #expect(await f.probe.localStarts == 2)
        #expect(try await f.store.recording(id: id)?.recognitionState == .completed)
        #expect(f.factory.configuration == f.config)
        try await f.cleanup()
    }

    @Test func rateLimitUsesLocalThenWaitsAtLeastServerBackoffBeforeNextCloudProbe() async throws {
        let f = try OfflineFixture()
        await f.probe.setFailure(.rateLimited)
        try await f.worker.beginUtterance()
        let first = try #require(await f.worker.recordingID)
        try await f.worker.append(Data(repeating: 8, count: 640)); try await f.worker.endUtterance(); await f.drain()
        #expect(await f.probe.localStarts == 1)
        #expect(try await f.store.recording(id: first)?.recognitionState == .completed)
        let starts = await f.probe.cloudStarts
        f.clock.advance(59)
        try await f.worker.beginUtterance()
        try await f.worker.append(Data(repeating: 9, count: 640)); try await f.worker.endUtterance(); await f.drain()
        #expect(await f.probe.cloudStarts == starts)
        #expect(await f.probe.localStarts == 2)
        await f.probe.setFailure(nil); f.clock.advance(2)
        try await f.worker.beginUtterance()
        let next = try #require(await f.worker.recordingID)
        try await f.worker.append(Data(repeating: 10, count: 640)); try await f.worker.endUtterance(); await f.drain()
        #expect(await f.probe.cloudStarts == starts + 1)
        #expect(try await f.store.recording(id: next)?.recognitionState == .completed)
        try await f.cleanup()
    }

    @Test func localFinalConflictingWithExternalPrefixCannotClaimCompletion() async throws {
        let f = try OfflineFixture()
        let binding = try await f.store.createBinding(label: "synthetic conflict")
        let record = try await f.store.createRecording()
        let firstTicket = try await f.store.beginRecognition(recordingID: record.id)
        let first = LocalCandidateIngress(store: f.store, ticket: firstTicket)
        try await first.receive(.init(text: "hello", stableUTF16Length: 5, audioEndSeconds: 1, isComplete: true))
        try await first.finish()
        let revision = try #require(await f.store.latestDispatchableRevision(recordingID: record.id))
        let reserved = try #require(await f.store.reserveDispatch(bindingID: binding, recordingID: record.id,
            revisionID: revision.id, stableUTF16End: 5))
        try await f.store.completeDispatch(id: reserved.id, state: .unverified)
        let nextTicket = try await f.store.beginRecognition(recordingID: record.id)
        let next = LocalCandidateIngress(store: f.store, ticket: nextTicket)
        try await next.receive(.init(text: "other", stableUTF16Length: 5, audioEndSeconds: 1, isComplete: true))
        await #expect(throws: ProviderFailure.self) { try await next.finish() }
        #expect(try await f.store.recording(id: record.id)?.recognitionState != .completed)
        #expect(try await f.store.fusionReservedPrefix(recordingID: record.id) == "hello")
        #expect(try await f.store.dispatchState(id: reserved.id) == .unverified)
        #expect(try await f.store.recognitionCandidates(recordingID: record.id).count == 2)
        try await f.cleanup()
    }

    @Test func circuitCoalescesFailuresBoundsProbesAndSeparatesAuthorization() throws {
        let clock = FailoverClock(), epoch = RecognitionFailoverEpoch(now: { Date(timeIntervalSince1970: 100) })
        #expect(epoch.admitCloud().0)
        epoch.failed(.connection, probe: nil)
        epoch.failed(.connection, probe: nil)
        #expect(!epoch.admitCloud().0)
        let bounded = RecognitionFailoverEpoch(now: { clock.now() })
        bounded.failed(.connection, probe: nil)
        for _ in 0..<3 {
            clock.advance(100)
            let admission = bounded.admitCloud()
            #expect(admission.0); #expect(admission.1 != nil)
            #expect(!bounded.admitCloud().0)
            bounded.failed(.connection, probe: admission.1)
        }
        clock.advance(10_000); #expect(!bounded.admitCloud().0)
        for reason in [ProviderFailure.authorization, .permission, .regionMismatch, .quota,
                       .configuration("synthetic"), .protocolViolation("synthetic")] {
            let blocked = RecognitionFailoverEpoch(now: { clock.now() })
            blocked.failed(reason, probe: nil); clock.advance(10_000)
            #expect(!blocked.admitCloud().0)
        }
        let cancelled = RecognitionFailoverEpoch(now: { clock.now() })
        cancelled.failed(.cancelled, probe: nil); #expect(cancelled.admitCloud().0)
        let limited = RecognitionFailoverEpoch(now: { clock.now() })
        limited.failed(.connection, probe: nil)
        limited.failed(.rateLimited, probe: nil)
        clock.advance(59); #expect(!limited.admitCloud().0)
        clock.advance(2); #expect(limited.admitCloud().0)
    }
}
