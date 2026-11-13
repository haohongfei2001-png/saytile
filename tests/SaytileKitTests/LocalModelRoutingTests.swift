import Foundation
import Testing
@testable import SaytileKit

@Suite("Per-recording local model routing")
struct LocalModelRoutingTests {
    @Test(arguments: [false, true]) func captureFreezesEndpointAtOnsetAndUpdatesItForTheNextUtterance(startWithCloud: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let local = RecognitionConfiguration(), cloud = HostedTransport.configuration
        let factory = RecognitionSessionFactory(configuration: startWithCloud ? cloud : local)
        let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 320), sampleRate: 16_000,
                                       recognitionEnabled: false, recognitionFactory: factory,
                                       update: { _, _ in }, failed: { Issue.record("Capture interrupted: \($0)") })
        let tone = (0..<3200).map { i in
            let t = Double(i) / 16_000
            return Int16(10_000 * sin(2 * .pi * 120 * t) + 4_000 * sin(2 * .pi * 660 * t))
        }
        let speech = tone.withUnsafeBytes { Data($0) }
        let pause = Data(repeating: 0, count: 57_600) // 1.8 s, between the two endpoint policies.
        try await worker.acceptPCM(speech)
        try #require(await worker.recordingID != nil)
        factory.update(startWithCloud ? local : cloud, nextUtteranceOnly: true)
        try await worker.acceptPCM(pause)
        #expect((await worker.recordingID != nil) == startWithCloud)
        try await worker.acceptPCM(Data(repeating: 0, count: 32_000))
        #expect(await worker.recordingID == nil)
        try await worker.acceptPCM(speech)
        try #require(await worker.recordingID != nil)
        try await worker.acceptPCM(pause)
        #expect((await worker.recordingID != nil) == !startWithCloud)
        try await worker.flushTail()
        #expect(try await store.listRecordings().count == 2)
        try await store.close()
    }

    @Test func endpointLimitsFollowTheEffectiveRouteAndKeepPreviouslyCapturedValues() {
        let cloud = HostedTransport.configuration
        let factory = RecognitionSessionFactory(configuration: cloud)
        let byok = factory.snapshot
        let local = VoiceSegmenter.Limits()
        #expect(byok.captureLimits == .init(endSilenceFrames: 100, maximumFrames: 15_000))
        #expect(byok.localOnly.captureLimits == local)
        factory.select(.local, revoke: false)
        #expect(factory.snapshot.captureLimits == local)
        let expired = HostedAccess(origin: URL(fileURLWithPath: "/"), bearer: "", expiry: .distantPast)
        factory.select(.connected(expired), revoke: false)
        #expect(factory.snapshot.captureLimits == local)
        let current = HostedAccess(origin: URL(fileURLWithPath: "/"), bearer: "", expiry: .distantFuture)
        factory.select(.connected(current), revoke: false)
        let hosted = factory.snapshot
        #expect(hosted.captureLimits == .init(endSilenceFrames: 100, maximumFrames: 1_500))
        factory.select(.byok, revoke: true)
        factory.update(RecognitionConfiguration(), nextUtteranceOnly: true)
        #expect(factory.snapshot.captureLimits == local)
        #expect(hosted.captureLimits.maximumFrames == 1_500)
        #expect(byok.captureLimits.maximumFrames == 15_000)
    }

    @Test func missingEngineKeepsOriginalAudioAndOnlyChangesFutureLiveTickets() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let service = LocalASRService(root: root.appending(path: "MissingModels"))
        let factory = RecognitionSessionFactory()
        let calls = AsyncStream<LocalASRID>.makeStream()
        factory.selectLocal(live: .qwen, archive: .qwenLarge, service: service) { id in
            calls.continuation.yield(id)
            factory.selectLocal(live: .sherpa, archive: .qwenLarge, service: service)
        }
        let initial = factory.snapshot
        let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 320), sampleRate: 16_000,
            recognitionFactory: factory, update: { _, _ in }, failed: { Issue.record("Capture interrupted: \($0)") })
        let pcm = Data(repeating: 0x21, count: 1_920)
        try await worker.beginUtterance()
        let first = try #require(await worker.recordingID)
        let firstSession = try #require(await worker.speech)
        await firstSession.wait()
        try await worker.append(pcm)
        try await worker.endUtterance()
        let record = try #require(try await store.recording(id: first))
        #expect(record.recognitionState == .failed && record.audioState == .available)
        let runs = try await store.modelRuns(recordingID: first)
        #expect(runs.map(\.ticket.configurationID) == [LocalASRID.qwen.evidenceID])
        let chunks = try await store.audioChunks(recordingID: first)
        #expect(chunks.count == 1)
        let chunk = try #require(chunks.first)
        let wave = try Data(contentsOf: await store.audioURL(for: chunk))
        #expect(wave.count == 44 + pcm.count && wave.dropFirst(44) == pcm)

        // An old archive ticket must not cause a second live reconfiguration.
        // Both replacement assets deliberately remain absent in this routing test.
        for (snapshot, archived, expected) in [(initial, true, LocalASRID.qwenLarge), (factory.snapshot, false, .sherpa)] {
            let record = try await store.createRecording()
            let ticket = try await store.beginRecognition(recordingID: record.id)
            let session = factory.make(store: store, ticket: ticket, snapshot: snapshot,
                                       archived: archived, newCapture: !archived)
            session.finish()
            await session.wait()
            let recorded = try await store.modelRuns(recordingID: record.id)
            #expect(recorded.map(\.ticket.configurationID) == [expected.evidenceID])
        }
        calls.continuation.finish()
        var reported: [LocalASRID] = []
        for await id in calls.stream { reported.append(id) }
        #expect(reported == [.qwen])
        try await store.close()
    }
}

