import Foundation
import Testing
@testable import SaytileKit

@Suite("Per-recording local model routing")
struct LocalModelRoutingTests {
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

