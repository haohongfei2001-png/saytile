import Foundation
import Testing
@testable import SaytileKit

/// Models the synchronous Keychain call without touching Keychain. Revocation
/// happens after the read enters and before its synthetic result is returned.
private final class CredentialReadBarrier: @unchecked Sendable {
    let purpose: RecognitionPurpose
    private let onRead: @Sendable () -> Void
    private let condition = NSCondition()
    private var entered = false
    private var released = false
    private var returned = false
    private var timedOut = false
    private var providers: [CloudProvider: Int] = [:]
    private var reviewCalls = 0
    init(purpose: RecognitionPurpose, onRead: @escaping @Sendable () -> Void) {
        self.purpose = purpose
        self.onRead = onRead
    }
    func read(_ configuration: ModelConfiguration) -> String {
        guard configuration.purpose == purpose else { return "synthetic-fixture-credential" }
        condition.lock(); defer { condition.unlock() }
        entered = true
        onRead()
        let deadline = Date().addingTimeInterval(5)
        while !released {
            if !condition.wait(until: deadline) { timedOut = true; break }
        }
        returned = true
        return "synthetic-read-result-after-revocation"
    }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
    func started(_ provider: CloudProvider) { condition.lock(); providers[provider, default: 0] += 1; condition.unlock() }
    func reviewed() { condition.lock(); reviewCalls += 1; condition.unlock() }
    var snapshot: (entered: Bool, returned: Bool, timedOut: Bool, providers: [CloudProvider: Int], reviews: Int) {
        condition.lock(); defer { condition.unlock() }
        return (entered, returned, timedOut, providers, reviewCalls)
    }
}

private struct ReadRevocationProvider: StreamingASRProvider {
    let barrier: CredentialReadBarrier
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        barrier.started(configuration.provider)
        var count = 0
        for await data in audio { try Task.checkCancellation(); count += data.count }
        try Task.checkCancellation()
        try await emit(.init(text: "不要发送", stableUTF16Length: 4, audioEndSeconds: Double(count) / 32_000,
                             timingGranularity: "utterance", isComplete: true))
    }
}

private final class UnexpectedReadRevocationLocalSession: RecognitionSession, @unchecked Sendable {
    let recordingID: UUID
    let isComplete = true
    init(_ id: UUID) { recordingID = id; Issue.record("Credential revocation must not start unrelated recognition") }
    func append(_ data: Data) {}
    func finish() {}
    func cancel() {}
    func wait() async {}
}

@Suite("Credential reads cannot outlive their cloud authorization")
struct CredentialReadRevocationTests {
    @Test(.timeLimit(.minutes(1)), arguments: [RecognitionPurpose.chineseASR, .textFusion])
    func revocationDuringSynchronousCredentialReadPreventsSubsequentRequest(purpose: RecognitionPurpose) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-credential-read-revocation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let record = try await store.createRecording()
        let pcm = Data((0..<640).map { UInt8($0 % 251) })
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk(); try journal.append(pcm); try journal.closeChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: journal.frames)
        try await store.finishRecording(id: record.id)
        let ticket = try await store.beginFusionRecognition(recordingID: record.id)
        var configuration = RecognitionConfiguration(); configuration.languagePreference = .chinese; configuration.cloudEnabled = true
        for index in configuration.models.indices {
            configuration.models[index].cloudConsent = true
            if configuration.models[index].provider == .qwenMessage { configuration.models[index].workspaceID = "isolated-read" }
        }
        let (readEvents, readSignal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let barrier = CredentialReadBarrier(purpose: purpose) { readSignal.yield(()) }
        defer { barrier.release() }
        let epoch = RecognitionFailoverEpoch(now: Date.init)
        let dependencies = RecognitionPipelineDependencies(credential: { barrier.read($0) },
            streaming: { _ in ReadRevocationProvider(barrier: barrier) },
            transcribe: { _, _, _ in throw ProviderFailure.incomplete },
            arbitrate: { evidence, _, _, _, _ in
                barrier.reviewed()
                guard let source = evidence.first else { throw ProviderFailure.incomplete }
                return (.init(selections: [.init(candidateID: source.candidateID, utf16Start: 0, utf16End: source.text.utf16.count)],
                              unresolved: false, needsAudioReview: false, reasonCode: "synthetic-read"),
                        .init(requestID: nil, inputTokens: nil, outputTokens: nil, elapsedSeconds: 0))
            }, listen: { _, _, _ in throw ProviderFailure.incomplete })
        let session = FailoverRecognitionSession(store: store, ticket: ticket, configuration: configuration,
            dependencies: dependencies,
            local: .init(availability: { .init(supported: false, installed: false, message: "isolated fixture") },
                         make: { _, ticket in UnexpectedReadRevocationLocalSession(ticket.recordingID) }),
            epoch: epoch, cloud: true, probe: nil, onComplete: { readSignal.finish() })
        defer { session.cancel() }
        session.append(pcm); session.finish()
        // The text read follows ASR publication. Revoke at the actual credential
        // boundary, even if preparing that candidate takes longer on a busy runner.
        var reads = readEvents.makeAsyncIterator()
        let didStartReading = await reads.next() != nil
        try #require(didStartReading, "The selected credential must be read before the session ends.")
        #expect(barrier.snapshot.entered)
        #expect(!barrier.snapshot.returned)
        epoch.invalidate()
        barrier.release()
        let completionDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !session.isComplete && ContinuousClock.now < completionDeadline { try await Task.sleep(for: .milliseconds(2)) }
        #expect(session.isComplete)
        session.cancel(); await session.wait()
        let observed = barrier.snapshot
        #expect(observed.returned && !observed.timedOut)
        #expect(observed.reviews == 0)
        if purpose == .chineseASR {
            #expect(observed.providers[.qwenMessage, default: 0] == 0)
        } else {
            #expect(observed.providers.values.reduce(0, +) > 0)
            #expect(try await !store.recognitionCandidates(recordingID: record.id).isEmpty)
        }
        let chunk = try #require(await store.audioChunks(recordingID: record.id).first)
        #expect(try Data(contentsOf: await store.audioURL(for: chunk)).dropFirst(44) == pcm)
        #expect(try await store.recording(id: record.id)?.recognitionState != .running)
        try await store.close()
    }
}
