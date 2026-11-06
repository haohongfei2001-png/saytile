import Testing
@testable import SaytileKit

@Suite("Chunked playback seeking")
struct AudioPlaybackTests {
    @Test func seeksAcrossOriginalChunkBoundaries() {
        let timeline = AudioPlaybackTimeline(durations: [15, 15, 2.5])
        #expect(timeline.duration == 32.5)
        #expect(timeline.location(at: 15)?.index == 1)
        #expect(timeline.location(at: 15)?.offset == 0)
        #expect(timeline.location(at: 31)?.index == 2)
        #expect(timeline.location(at: 31)?.offset == 1)
        #expect(timeline.location(at: 5)?.index == 0)
        #expect(timeline.location(at: 5)?.offset == 5)
    }
    @Test func clampsEndAndRejectsInvalidDurations() {
        let timeline = AudioPlaybackTimeline(durations: [15, .nan, -1, 2])
        #expect(timeline.duration == 17)
        #expect(timeline.location(at: 90)?.offset == 2)
        #expect(timeline.location(at: -.infinity)?.offset == 0)
        #expect(AudioPlaybackTimeline(durations: []).location(at: 0) == nil)
    }
}

import Foundation

@Suite("Silent production AVAudioPlayer integration")
struct AudioPlayerIntegrationTests {
    @MainActor @Test func silentPlayerSeeksAcrossChunksAndReleasesDeletionLease() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-silent-player-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        for frames in [16_000, 9_600] {
            try journal.openChunk(); try journal.append(Data(repeating: 0, count: frames * 2)); try journal.closeChunk()
            try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: Int64(frames))
        }
        try await store.finishRecording(id: record.id)
        _ = try await store.saveEdit(recordingID: record.id, text: "静音回听测试文字")
        let controller = AudioController(store: store)
        try await controller.play(recordingID: record.id)
        #expect(controller.playingID == record.id)
        #expect(abs(controller.playbackDuration - 1.6) < 0.0001)
        try await Task.sleep(for: .milliseconds(180))
        #expect(controller.playbackPosition > 0)
        controller.seekPlayback(to: 1.15)
        #expect(abs(controller.playbackPosition - 1.15) < 0.0001)
        controller.seekPlayback(to: 0.1)
        #expect(abs(controller.playbackPosition - 0.1) < 0.0001)
        try await store.deleteAudio(recordingID: record.id)
        #expect(try await store.recording(id: record.id)?.audioState == .deletePending)
        controller.stopPlayback()
        await controller.shutdown()
        #expect(controller.playingID == nil)
        #expect(controller.state == .paused)
        #expect(try await store.recording(id: record.id)?.audioState == .deleted)
        #expect(try await store.recording(id: record.id)?.text == "静音回听测试文字")
        try await store.close()
    }
    @MainActor @Test func silentPlayerNaturallyFinishesWithoutStartingMicrophone() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-silent-finish-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk(); try journal.append(Data(repeating: 0, count: 8_000)); try journal.closeChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: 4_000)
        try await store.finishRecording(id: record.id)
        let controller = AudioController(store: store)
        try await controller.play(recordingID: record.id)
        for _ in 0..<40 where controller.playingID != nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(controller.playingID == nil)
        #expect(controller.state == .paused)
        await controller.shutdown()
        try await store.close()
    }
}
