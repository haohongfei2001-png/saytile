import Foundation
import Testing
@testable import SaytileKit

@Suite("Journal range and local candidate integration")
struct JournalRangeAndLocalIngressTests {
    @Test(arguments: ["truncated-header", "wrong-format", "truncated-payload", "symlink", "stale-generation"])
    func rejectsChangedFilesAndRetiredTickets(reason: String) async throws {
        let directory = URL(fileURLWithPath: "/tmp/saytile-local-range-" + UUID().uuidString)
        let store = try SaytileStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try await store.createRecording()
        let ticket = try await store.beginRecognition(recordingID: record.id)
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk()
        let pcm = Data(repeating: 42, count: 640)
        try journal.append(pcm); try journal.closeChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: journal.durableFrames)
        let chunk = try #require(await store.audioChunks(recordingID: record.id).first)
        let url = try await store.audioURL(for: chunk)
        var bytes = try Data(contentsOf: url)
        switch reason {
        case "truncated-header": try bytes.prefix(20).write(to: url)
        case "wrong-format": bytes[20] = 3; try bytes.write(to: url)
        case "truncated-payload": try bytes.dropLast(2).write(to: url)
        case "symlink":
            let outside = directory.appendingPathComponent("owned-nonaudio-fixture.bin")
            try bytes.write(to: outside)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        default:
            let replacement = try await store.beginRecognition(recordingID: record.id)
            #expect(try await store.readPCMRange(ticket: replacement, startFrame: 0, frameCount: 320) == pcm)
        }
        await #expect(throws: (any Error).self) {
            try await store.readPCMRange(ticket: ticket, startFrame: 0, frameCount: 320)
        }
        try await store.close()
    }

    @Test func exactDurableRangeCrossesChunksAfterTwelveMBWithoutLifetimeBuffer() async throws {
        let directory = URL(fileURLWithPath: "/tmp/saytile-single-20261107-journal-" + UUID().uuidString)
        let store = try SaytileStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try await store.createRecording()
        let ticket = try await store.beginRecognition(recordingID: record.id)
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        // 13.44 MB generated in bounded chunks; accelerated, not a wall-clock soak.
        for index in 0..<28 {
            try journal.openChunk()
            try journal.append(Data(repeating: UInt8(index), count: 480_000))
            try journal.closeChunk()
            try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: journal.durableFrames)
        }
        let range = try await store.readPCMRange(ticket: ticket, startFrame: 26 * 240_000 - 2, frameCount: 5)
        #expect(range == Data(repeating: 25, count: 4) + Data(repeating: 26, count: 6))
        try journal.openChunk()
        try journal.append(Data(repeating: 99, count: 64))
        try journal.checkpoint()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: journal.durableFrames)
        try journal.append(Data(repeating: 100, count: 64)) // physically present, not durable/published
        await #expect(throws: StoreError.self) {
            try await store.readPCMRange(ticket: ticket, startFrame: 28 * 240_000 + 31, frameCount: 2)
        }
        await #expect(throws: StoreError.self) { try await store.readPCMRange(ticket: ticket, startFrame: 0, frameCount: 524_289) }
        try journal.closeChunk()
        try await store.finishRecording(id: record.id)
        try await store.deleteAudio(recordingID: record.id)
        await #expect(throws: (any Error).self) { try await store.readPCMRange(ticket: ticket, startFrame: 0, frameCount: 2) }
        try await store.close()
    }

    @Test func offlineEvidenceUsesCandidatePublicationAndProtectsUserDraft() async throws {
        let directory = URL(fileURLWithPath: "/tmp/saytile-single-20261107-local-" + UUID().uuidString)
        let store = try SaytileStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try await store.createRecording()
        let ticket = try await store.beginRecognition(recordingID: record.id)
        let ingress = LocalCandidateIngress(store: store, ticket: ticket)
        try await ingress.receive(.init(text: "不要删😀", stableUTF16Length: 5, audioEndSeconds: 1, isComplete: false))
        #expect(try await store.recognitionCandidates(recordingID: record.id).count == 1)
        #expect(try await store.recording(id: record.id)?.text == "不要删😀")
        _ = try await store.saveEdit(recordingID: record.id, text: "我的修改")
        try await ingress.receive(.init(text: "不要删😀，不要", stableUTF16Length: 8, audioEndSeconds: 2, isComplete: true))
        try await ingress.finish()
        let candidates = try await store.recognitionCandidates(recordingID: record.id)
        #expect(candidates.count == 2)
        #expect(candidates.allSatisfy { $0.run.provider == "apple-speech-analyzer" })
        #expect(try await store.recording(id: record.id)?.text == "我的修改")
        #expect(try await store.fusionDecisions(recordingID: record.id).count == 2)
        #expect(try await store.recording(id: record.id)?.recognitionState == .completed)
        try await store.finishRecording(id: record.id)
        try await store.deleteAudio(recordingID: record.id)
        await #expect(throws: (any Error).self) {
            try await ingress.receive(.init(text: "迟到", stableUTF16Length: 2, audioEndSeconds: 2, isComplete: true))
        }
        #expect(try await store.recording(id: record.id)?.text == "我的修改")
        try await store.close()
    }
}
