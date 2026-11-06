import Foundation
import Testing
@testable import SaytileKit

private enum CoordinatorFixtureFailure: Error { case timeout, unexpectedDependency }

/// Test-controlled gate with a bounded wait. No continuation can outlive a failed test.
private final class CoordinatorGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    func open() { lock.lock(); opened = true; lock.unlock() }
    private func isOpen() -> Bool { lock.lock(); defer { lock.unlock() }; return opened }
    func wait() async throws {
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !isOpen() {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw CoordinatorFixtureFailure.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
        try Task.checkCancellation()
    }
    func waitIgnoringCancellation() async throws {
        // Simulate a vendor callback already in flight when the owner cancels. The
        // detached wait still has the same deadline, and cleanup opens every gate.
        try await Task.detached { try await self.wait() }.value
    }
}

private actor CoordinatorProviderProbe {
    private(set) var received = Data()
    private(set) var callbackAttempts = 0
    private(set) var acceptedCallbacks = 0
    private(set) var rejectedCallbacks = 0
    func append(_ data: Data) { received.append(data) }
    func attempting() { callbackAttempts += 1 }
    func accepted() { acceptedCallbacks += 1 }
    func rejected() { rejectedCallbacks += 1 }
}

private struct CoordinatorProviderControl: Sendable {
    let release = CoordinatorGate()
    let firstFrame = CoordinatorGate()
    let audioEnded = CoordinatorGate()
    let callbackEnded = CoordinatorGate()
    let probe = CoordinatorProviderProbe()
    let text: String
    var failAfterFirstFrame = false
    var ignoreCancellation = false
}

private struct CoordinatorFakeProvider: StreamingASRProvider {
    let control: CoordinatorProviderControl
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        var bytes = 0
        for await frame in audio {
            await control.probe.append(frame)
            bytes += frame.count
            control.firstFrame.open()
            if control.failAfterFirstFrame {
                try await control.release.wait()
                throw ProviderFailure.connection
            }
        }
        control.audioEnded.open()
        if control.ignoreCancellation { try await control.release.waitIgnoringCancellation() }
        else { try await control.release.wait() }
        await control.probe.attempting()
        do {
            try await emit(.init(text: control.text, stableUTF16Length: control.text.utf16.count,
                                 audioEndSeconds: Double(bytes) / 32_000, isComplete: true,
                                 requestID: "offline-" + configuration.id.uuidString))
            await control.probe.accepted()
            control.callbackEnded.open()
        } catch {
            await control.probe.rejected()
            control.callbackEnded.open()
            throw error
        }
    }
}

private actor CoordinatorReviewProbe {
    private(set) var listened: [Data] = []
    private(set) var arbitrationCalls = 0
    func hear(_ data: Data) { listened.append(data) }
    func arbitrate(_ evidence: [ReviewEvidence]) throws -> PrecisionReviewDecision {
        arbitrationCalls += 1
        let acoustic = evidence.first { $0.role == RecognitionPurpose.audioReview.rawValue }
        guard let selected = acoustic ?? evidence.first(where: { $0.role == RecognitionPurpose.englishASR.rawValue }) else {
            throw CoordinatorFixtureFailure.unexpectedDependency
        }
        return .init(selections: [.init(candidateID: selected.candidateID, utf16Start: 0, utf16End: selected.text.utf16.count)],
                     unresolved: acoustic == nil, needsAudioReview: acoustic == nil, reasonCode: "offline-evidence-selection")
    }
}

private final class CoordinatorHarness: Sendable {
    let directory: URL
    let store: SaytileStore
    let recordingID: UUID
    let bindingID: UUID
    let ticket: RecognitionTicket
    let file: URL
    let relativePath: String
    let session: MultiRecognitionSession
    let completed: CoordinatorGate
    let chinese: CoordinatorProviderControl
    let english: CoordinatorProviderControl
    let review: CoordinatorReviewProbe

    init(mode: InputQualityMode, chinese: CoordinatorProviderControl, english: CoordinatorProviderControl,
         initialPCM: Data, reviewText: String? = nil) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-coordinator-" + UUID().uuidString)
        let store = try SaytileStore(directory: directory)
        let binding = try await store.createBinding(label: "Offline coordinator fixture")
        let recording = try await store.createRecording()
        let path = recording.id.uuidString + "/fixture.wav"
        let file = store.audioDirectory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.writePCM(initialPCM, to: file)
        try await store.registerAudioChunk(recordingID: recording.id, relativePath: path, frames: Int64(initialPCM.count / 2))
        var config = RecognitionConfiguration()
        config.cloudEnabled = true
        config.inputMode = mode
        config.models = [
            .init(purpose: .chineseASR, provider: .qwenMessage, model: "qwen-audio-3.1-asr-flash-message",
                  cloudConsent: true, region: "cn-beijing", workspaceID: "offline-fixture"),
            .init(purpose: .englishASR, provider: .assemblyAI, model: "universal-3-6-pro", cloudConsent: true)
        ]
        let review = CoordinatorReviewProbe()
        if reviewText != nil {
            config.models += [
                .init(purpose: .textFusion, provider: .openAIResponses, model: "offline-text-review", cloudConsent: true),
                .init(purpose: .audioReview, provider: .gemini, model: "offline-audio-review", cloudConsent: true)
            ]
        }
        let dependencies = RecognitionPipelineDependencies(
            // A non-secret sentinel satisfies configuration validation. Never read Keychain.
            credential: { _ in "offline-fixture-not-an-api-key" },
            streaming: { provider in
                switch provider {
                case .qwenMessage: return CoordinatorFakeProvider(control: chinese)
                case .assemblyAI: return CoordinatorFakeProvider(control: english)
                default: throw CoordinatorFixtureFailure.unexpectedDependency
                }
            },
            transcribe: { _, _, _ in throw CoordinatorFixtureFailure.unexpectedDependency },
            arbitrate: { evidence, _, _, _, _ in
                let decision = try await review.arbitrate(evidence)
                return (decision, .init(requestID: "offline-text", inputTokens: nil, outputTokens: nil, elapsedSeconds: 0))
            },
            listen: { data, _, _ in
                guard let reviewText else { throw CoordinatorFixtureFailure.unexpectedDependency }
                await review.hear(data)
                return (.init(text: reviewText, uncertain: false),
                        .init(requestID: "offline-audio", inputTokens: nil, outputTokens: nil, elapsedSeconds: 0))
            })
        let ticket = try await store.beginFusionRecognition(recordingID: recording.id, mode: mode)
        let completed = CoordinatorGate()
        self.directory = directory; self.store = store; self.recordingID = recording.id
        self.bindingID = binding; self.ticket = ticket; self.file = file; self.relativePath = path
        self.completed = completed; self.chinese = chinese; self.english = english; self.review = review
        self.session = MultiRecognitionSession(store: store, ticket: ticket, configuration: config,
                                               dependencies: dependencies, onComplete: { completed.open() })
    }
    private static func writePCM(_ pcm: Data, to file: URL) throws {
        let contents = PCMJournal.header(frames: Int64(pcm.count / 2)) + pcm
        try contents.write(to: file, options: .atomic)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.synchronize()
    }
    func persist(_ pcm: Data) async throws {
        try Self.writePCM(pcm, to: file)
        try await store.registerAudioChunk(recordingID: recordingID, relativePath: relativePath, frames: Int64(pcm.count / 2))
    }
    func endRecording() async throws {
        try await store.finishRecording(id: recordingID)
        session.finish()
    }
    func wait() async throws {
        try await completed.wait()
        await session.wait()
    }
    func cleanup() async {
        session.cancel()
        chinese.release.open(); english.release.open()
        do { try await wait() } catch { Issue.record("Coordinator fixture did not terminate within its deadline") }
        try? await store.finishRecording(id: recordingID)
        try? await store.close()
        try? FileManager.default.removeItem(at: directory)
    }
}

private func withCoordinatorHarness(mode: InputQualityMode = .highestQuality,
                                    chinese: CoordinatorProviderControl, english: CoordinatorProviderControl,
                                    initialPCM: Data, reviewText: String? = nil,
                                    body: (CoordinatorHarness) async throws -> Void) async throws {
    let harness = try await CoordinatorHarness(mode: mode, chinese: chinese, english: english,
                                              initialPCM: initialPCM, reviewText: reviewText)
    do { try await body(harness) }
    catch { await harness.cleanup(); throw error }
    await harness.cleanup()
}

private func coordinatorEventually(_ condition: @Sendable () async throws -> Bool) async throws {
    let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while try await !condition() {
        guard clock.now < deadline else { throw CoordinatorFixtureFailure.timeout }
        try await Task.sleep(for: .milliseconds(5))
    }
}

@Suite("Real coordinator with isolated persistence and controlled providers")
struct RecognitionCoordinatorTests {
    private var firstPCM: Data { Data(repeating: 1, count: 16_000) }
    private var secondPCM: Data { Data(repeating: 2, count: 16_000) }

    @Test func identicalAudioWaitsForBothExpertsBeforeQualityPublication() async throws {
        let first = firstPCM, second = secondPCM, pcm = first + second
        let chinese = CoordinatorProviderControl(text: "我用 SwiftUI。")
        let english = CoordinatorProviderControl(text: "我用 SwiftUI。")
        try await withCoordinatorHarness(chinese: chinese, english: english, initialPCM: pcm) { h in
            h.session.append(first); h.session.append(second)
            try await h.endRecording()
            try await chinese.audioEnded.wait(); try await english.audioEnded.wait()
            #expect(await chinese.probe.received == pcm)
            #expect(await english.probe.received == pcm)
            chinese.release.open()
            try await chinese.callbackEnded.wait()
            #expect(try await h.store.latestDispatchableRevision(recordingID: h.recordingID) == nil)
            #expect(try await h.store.recognitionCandidates(recordingID: h.recordingID).count == 1)
            #expect(!h.session.isComplete)
            english.release.open()
            try await h.wait()
            #expect(try await h.store.latestDispatchableRevision(recordingID: h.recordingID)?.text == chinese.text)
            #expect(try await h.store.recording(id: h.recordingID)?.recognitionState == .completed)
            #expect(try await h.store.modelRuns(recordingID: h.recordingID).allSatisfy { $0.state == .completed })
        }
    }

    @Test func failedExpertDoesNotStopOtherAudioOrDestroyOriginal() async throws {
        let first = firstPCM, second = secondPCM, pcm = first + second
        let chinese = CoordinatorProviderControl(text: "unused", failAfterFirstFrame: true)
        let english = CoordinatorProviderControl(text: "原音继续保存。")
        try await withCoordinatorHarness(chinese: chinese, english: english, initialPCM: first) { h in
            h.session.append(first)
            try await chinese.firstFrame.wait(); try await english.firstFrame.wait()
            chinese.release.open()
            try await coordinatorEventually {
                try await h.store.modelRuns(recordingID: h.recordingID).contains { $0.ticket.purpose == .chineseASR && $0.state == .failed }
            }
            #expect(try await h.store.recording(id: h.recordingID)?.isRecording == true)
            #expect(try Data(contentsOf: h.file) == PCMJournal.header(frames: Int64(first.count / 2)) + first)
            // Capture persists the later frames even after one recognizer failed.
            try await h.persist(pcm)
            h.session.append(second)
            try await h.endRecording()
            try await english.audioEnded.wait()
            english.release.open()
            try await h.wait()
            #expect(await english.probe.received == pcm)
            #expect(try Data(contentsOf: h.file) == PCMJournal.header(frames: Int64(pcm.count / 2)) + pcm)
            #expect(try await h.store.audioChunks(recordingID: h.recordingID).first?.frames == Int64(pcm.count / 2))
            #expect(try await h.store.recording(id: h.recordingID)?.audioState == .available)
            #expect(try await h.store.recognitionCandidates(recordingID: h.recordingID).map(\.text) == [english.text])
            #expect(try await h.store.latestDispatchableRevision(recordingID: h.recordingID) == nil)
            let runs = try await h.store.modelRuns(recordingID: h.recordingID)
            #expect(runs.contains { $0.ticket.purpose == .englishASR && $0.state == .completed })
        }
    }

    @Test func audioDeletionInvalidatesEpochBeforeLateCallbacks() async throws {
        let pcm = firstPCM + secondPCM
        let chinese = CoordinatorProviderControl(text: "迟到中文", ignoreCancellation: true)
        let english = CoordinatorProviderControl(text: "late English", ignoreCancellation: true)
        try await withCoordinatorHarness(chinese: chinese, english: english, initialPCM: pcm) { h in
            h.session.append(pcm)
            try await h.endRecording()
            try await chinese.audioEnded.wait(); try await english.audioEnded.wait()
            try await h.store.deleteAudio(recordingID: h.recordingID)
            #expect(try await !h.store.isRecognitionCurrent(ticket: h.ticket))
            chinese.release.open(); english.release.open()
            try await h.wait()
            #expect(await chinese.probe.callbackAttempts == 1)
            #expect(await english.probe.callbackAttempts == 1)
            #expect(await chinese.probe.rejectedCallbacks == 1)
            #expect(await english.probe.rejectedCallbacks == 1)
            #expect(try await h.store.recognitionCandidates(recordingID: h.recordingID).isEmpty)
            #expect(try await h.store.revisions(recordingID: h.recordingID).isEmpty)
            #expect(try await h.store.latestDispatchableRevision(recordingID: h.recordingID) == nil)
            #expect(try await h.store.recording(id: h.recordingID)?.audioState == .deleted)
            #expect(!FileManager.default.fileExists(atPath: h.file.path))
        }
    }

    @Test func cancellationRejectsInFlightCallbacksWithoutErasingAudio() async throws {
        let pcm = firstPCM + secondPCM
        let chinese = CoordinatorProviderControl(text: "取消后迟到", ignoreCancellation: true)
        let english = CoordinatorProviderControl(text: "late after cancel", ignoreCancellation: true)
        try await withCoordinatorHarness(chinese: chinese, english: english, initialPCM: pcm) { h in
            h.session.append(pcm)
            try await h.endRecording()
            try await chinese.audioEnded.wait(); try await english.audioEnded.wait()
            h.session.cancel()
            chinese.release.open(); english.release.open()
            try await h.wait()
            #expect(await chinese.probe.callbackAttempts == 1)
            #expect(await english.probe.callbackAttempts == 1)
            #expect(await chinese.probe.acceptedCallbacks == 0)
            #expect(await english.probe.acceptedCallbacks == 0)
            #expect(try await h.store.recognitionCandidates(recordingID: h.recordingID).isEmpty)
            #expect(try await h.store.latestDispatchableRevision(recordingID: h.recordingID) == nil)
            #expect(try Data(contentsOf: h.file) == PCMJournal.header(frames: Int64(pcm.count / 2)) + pcm)
            #expect(try await h.store.recording(id: h.recordingID)?.audioState == .available)
        }
    }

    @Test func fastDispatchKeepsLateAcousticCorrectionInternal() async throws {
        let pcm = firstPCM + secondPCM
        let original = "支付15元。", corrected = "支付50元。"
        let chinese = CoordinatorProviderControl(text: original)
        let english = CoordinatorProviderControl(text: corrected)
        try await withCoordinatorHarness(mode: .fast, chinese: chinese, english: english,
                                         initialPCM: pcm, reviewText: corrected) { h in
            h.session.append(pcm)
            try await h.endRecording()
            try await chinese.audioEnded.wait(); try await english.audioEnded.wait()
            chinese.release.open()
            try await chinese.callbackEnded.wait()
            let firstValue = try await h.store.latestDispatchableRevision(recordingID: h.recordingID)
            let first = try #require(firstValue)
            #expect(first.text == original)
            let reservationValue = try await h.store.reserveDispatch(bindingID: h.bindingID, recordingID: h.recordingID,
                                                                     revisionID: first.id, stableUTF16End: original.utf16.count)
            let reservation = try #require(reservationValue)
            try await h.store.completeDispatch(id: reservation.id, state: .unverified)
            english.release.open()
            try await h.wait()
            let head = try await h.store.latestDispatchableRevision(recordingID: h.recordingID)
            #expect(head?.id == first.id)
            #expect(head?.text == original)
            let revisions = try await h.store.revisions(recordingID: h.recordingID)
            let alternate = try #require(revisions.first { $0.text == corrected })
            #expect(alternate.id != first.id)
            #expect(try await h.store.dispatchState(id: reservation.id) == .unverified)
            #expect(try await h.store.reserveDispatch(bindingID: h.bindingID, recordingID: h.recordingID,
                                                     revisionID: first.id, stableUTF16End: original.utf16.count) == nil)
            await #expect(throws: StoreError.self) {
                try await h.store.reserveDispatch(bindingID: h.bindingID, recordingID: h.recordingID,
                                                  revisionID: alternate.id, stableUTF16End: corrected.utf16.count)
            }
            #expect(await h.review.arbitrationCalls > 0)
            let listened = await h.review.listened
            #expect(!listened.isEmpty)
            #expect(listened.allSatisfy { $0 == pcm })
            #expect(try await h.store.recognitionCandidates(recordingID: h.recordingID).contains { $0.run.purpose == .audioReview && $0.text == corrected })
        }
    }
}
