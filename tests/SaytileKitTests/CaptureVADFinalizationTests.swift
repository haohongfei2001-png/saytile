import CAudio
import Foundation
import Testing
@testable import SaytileKit

private enum CaptureProbeError: Error { case timedOut(String), missingEvidence }

private func waitForCapture(_ name: String, _ condition: () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while try await !condition() {
        guard ContinuousClock.now < deadline else { throw CaptureProbeError.timedOut(name) }
        try await Task.sleep(for: .milliseconds(5))
    }
}

private final class CaptureActivityProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var starts: [CloudProvider: Int] = [:]
    private var waiting = Set<CloudProvider>()
    private var released = false
    private var observations: [(speaking: Bool, level: Float)] = []

    func begin(_ provider: CloudProvider) -> Int {
        lock.withLock { starts[provider, default: 0] += 1; return starts[provider]! }
    }
    func holdFirstFinal(_ provider: CloudProvider) async throws {
        lock.withLock { _ = waiting.insert(provider) }
        try await waitForCapture("release of first final") { self.lock.withLock { self.released } }
    }
    func release() { lock.withLock { released = true } }
    func observe(_ speaking: Bool, _ level: Float) { lock.withLock { observations.append((speaking, level)) } }
    var selectedFinalHeld: Bool { lock.withLock { !released && waiting == [.qwenMessage] && starts[.assemblyAI] == nil } }
    var events: [(speaking: Bool, level: Float)] { lock.withLock { observations } }
}

private struct DelayedFinalExpert: StreamingASRProvider {
    let probe: CaptureActivityProbe
    func run(audio: AsyncStream<Data>, configuration: ModelConfiguration, credential: String,
             emit: @escaping @Sendable (ProviderTranscriptEvent) async throws -> Void) async throws {
        let number = probe.begin(configuration.provider)
        let segment = number == 1 ? "第一段" : "第二段"
        var bytes = 0
        for await block in audio {
            try Task.checkCancellation()
            let first = bytes == 0
            bytes += block.count
            if first {
                try await emit(.init(text: segment + "临时文字", stableUTF16Length: 0,
                    audioEndSeconds: Double(bytes) / 32_000, isComplete: false))
            }
        }
        if number == 1 { try await probe.holdFirstFinal(configuration.provider) }
        try Task.checkCancellation()
        let text = segment + "定稿"
        try await emit(.init(text: text, stableUTF16Length: text.utf16.count,
            audioEndSeconds: Double(bytes) / 32_000, timingGranularity: "utterance", isComplete: true))
    }
}

@Suite("Capture VAD activity during independent recognition finalization")
struct CaptureVADFinalizationTests {
    @Test func speechEndsAndRestartsWhileFirstExpertFinalsAreHeld() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-vad-final-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root), ring = try AudioRing(capacity: 131_072)
        let probe = CaptureActivityProbe()
        var config = RecognitionConfiguration(); config.languagePreference = .chinese; config.cloudEnabled = true; config.automaticRecovery = false
        for index in config.models.indices where config.models[index].enabled {
            config.models[index].cloudConsent = true
            if config.models[index].provider == .qwenMessage { config.models[index].workspaceID = "synthetic" }
        }
        let dependencies = RecognitionPipelineDependencies(credential: { _ in "synthetic-fixture" },
            streaming: { _ in DelayedFinalExpert(probe: probe) }, transcribe: { _, _, _ in throw CaptureProbeError.missingEvidence },
            arbitrate: { evidence, _, _, _, _ in
                guard let source = evidence.first(where: { $0.role == RecognitionPurpose.chineseASR.rawValue }) else { throw CaptureProbeError.missingEvidence }
                return (.init(selections: [.init(candidateID: source.candidateID, utf16Start: 0, utf16End: source.text.utf16.count)],
                    unresolved: false, needsAudioReview: false, reasonCode: "capture-fixture"),
                    .init(requestID: "synthetic", inputTokens: nil, outputTokens: nil, elapsedSeconds: 0))
            }, listen: { _, _, _ in throw CaptureProbeError.missingEvidence })
        var local = LocalFailoverDependencies.live
        local.availability = { .init(supported: false, installed: false, message: "synthetic-only") }
        let worker = try CaptureWorker(store: store, ring: ring, sampleRate: 16_000,
            recognitionFactory: .init(configuration: config, dependencies: dependencies, local: local),
            update: { probe.observe($0, $1) }, failed: { Issue.record("Synthetic capture failed: \($0)") })
        let sample = try CloudConnectionVerifier.bundledSample()
        let speech = sample.prefix(32_000).withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32_768 }
        }
        func write(_ frames: [Float]) {
            var frames = frames
            frames.withUnsafeMutableBufferPointer { samples in
                var channel = samples.baseAddress
                withUnsafePointer(to: &channel) { st_ring_write(ring.pointer, $0, 1, UInt32(samples.count)) }
            }
        }
        await worker.start()
        do {
            write(speech)
            try await waitForCapture("first actual VAD onset") { probe.events.last?.speaking == true }
            let firstID = try #require(await worker.recordingID)
            #expect(probe.events.contains { $0.speaking && $0.level > 0 })
            write([Float](repeating: 0, count: 48_000))
            try await waitForCapture("VAD end and selected expert final held") {
                probe.events.last?.speaking == false && probe.selectedFinalHeld
            }
            let first = try #require(try await store.recording(id: firstID))
            #expect(!first.isRecording && first.recognitionState == .running && first.audioState == .available)
            let chunks = try await store.audioChunks(recordingID: firstID)
            #expect(!chunks.isEmpty)
            var savedFrames: Int64 = 0
            for chunk in chunks {
                let wav = try Data(contentsOf: await store.audioURL(for: chunk))
                #expect(wav.prefix(4) == Data("RIFF".utf8) && wav.count == 44 + Int(chunk.frames) * 2)
                savedFrames += chunk.frames
            }
            #expect(savedFrames > 0)
            let beforeNext = probe.events.count
            write(speech)
            try await waitForCapture("second actual VAD onset and independent preview") {
                guard let id = await worker.recordingID, id != firstID, probe.events.last?.speaking == true else { return false }
                return try await store.recording(id: id)?.text == "第二段临时文字"
            }
            let secondID = try #require(await worker.recordingID)
            let onset = try #require(probe.events.indices.dropFirst(beforeNext).first(where: { probe.events[$0].speaking }))
            #expect(probe.selectedFinalHeld)
            probe.release()
            try await waitForCapture("old final committed") { try await store.recording(id: firstID)?.recognitionState == .completed }
            let complete = try #require(try await store.recording(id: firstID))
            let ongoing = try #require(try await store.recording(id: secondID))
            #expect(complete.text == "第一段定稿" && ongoing.text == "第二段临时文字" && ongoing.isRecording)
            #expect(await worker.recordingID == secondID && probe.events[onset...].allSatisfy(\.speaking))
            #expect(st_ring_dropped(ring.pointer) == 0)
            print("VAD_FINALIZATION first_wav_frames=\(savedFrames) first_eos_held=1 quiet_before_final=true next_speech_before_final=true old_final_on_original_id=true new_speech_active=true")
            await worker.stop()
            try await waitForCapture("second final committed") { try await store.recording(id: secondID)?.recognitionState == .completed }
            #expect(try await store.recording(id: secondID)?.text == "第二段定稿")
            for session in await worker.retired { await session.wait() }
            try await store.close()
        } catch {
            probe.release(); await worker.stop(); await worker.cancelRecognitionAndWait(); try? await store.close()
            throw error
        }
    }
}
