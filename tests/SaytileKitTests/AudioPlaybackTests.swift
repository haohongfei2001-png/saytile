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

import Combine
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
        var firstProgress: (instant: ContinuousClock.Instant, position: Double)?
        let observation = controller.$playbackPosition.first(where: { $0 > 0 }).sink { position in
            firstProgress = (.now, position)
        }
        defer { observation.cancel() }
        try await controller.play(recordingID: record.id)
        #expect(controller.playingID == record.id)
        #expect(abs(controller.playbackDuration - 1.6) < 0.0001)
        let start = ContinuousClock.now
        let deadline = start.advanced(by: .seconds(2))
        while firstProgress == nil, controller.playingID == record.id, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let receivedInTime = firstProgress.map { $0.instant <= deadline } == true
        #expect(receivedInTime, "The player must publish real positive progress within two seconds")
        #expect(controller.playingID == record.id, "Playback must still be active before seeking")
        #expect(controller.playbackPosition > 0)
        if let firstProgress {
            print("PLAYBACK_FIRST_PROGRESS position=\(firstProgress.position) after_play=\(start.duration(to: firstProgress.instant))")
        }
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

private actor PlaybackTransitionGate {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@Suite("Natural paragraph playback", .serialized)
struct ParagraphPlaybackTests {
    private func silentRecording(_ store: SaytileStore, frames: [Int], text: String = "独立回听资料") async throws -> UUID {
        let record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        for count in frames {
            try journal.openChunk(); try journal.append(Data(repeating: 0, count: count * 2)); try journal.closeChunk()
            try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: Int64(count))
        }
        try await store.finishRecording(id: record.id)
        _ = try await store.saveEdit(recordingID: record.id, text: text)
        return record.id
    }
    @MainActor private func waitFor(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(predicate())
    }

    @MainActor @Test func paragraphKeepsIdentitySeeksAcrossRecordingsAndSkipsMissingOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-paragraph-play-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let first = try await silentRecording(store, frames: [6_400, 4_800])
        let second = try await silentRecording(store, frames: [14_400])
        let deleted = try await silentRecording(store, frames: [8_000])
        try await store.deleteAudio(recordingID: deleted)
        let missing = try await silentRecording(store, frames: [8_000])
        let chunk = try #require(try await store.audioChunks(recordingID: missing).first)
        try FileManager.default.removeItem(at: await store.audioURL(for: chunk))
        let controller = AudioController(store: store)
        try await controller.play(recordingIDs: [first, deleted, missing, second, first], playbackID: first)
        #expect(controller.playingID == first && controller.playingRecordingID == first)
        #expect(abs(controller.playbackDuration - 1.6) < 0.0001)
        #expect(controller.playbackNotice == "有 2 段原音已删除或不可用，已跳过")
        controller.seekPlayback(to: 0.9)
        try await waitFor { controller.playingRecordingID == second }
        #expect(controller.playingID == first)
        #expect(controller.playbackPosition >= 0.9 && controller.playbackPosition < 1.5)
        controller.seekPlayback(to: 0.1)
        try await waitFor { controller.playingRecordingID == first && controller.playbackPosition < 0.4 }
        controller.stopPlayback(); await controller.shutdown()
        try await store.deleteAudio(recordingID: first)
        try await store.deleteAudio(recordingID: second)
        #expect(try await store.recording(id: first)?.audioState == .deleted)
        #expect(try await store.recording(id: second)?.audioState == .deleted)
        #expect(try await store.recording(id: deleted)?.text == "独立回听资料")
        try await store.close()
    }

    @MainActor @Test func actualPlayerContinuouslyFinishesTwoOriginalsWithoutMicrophone() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-paragraph-finish-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let first = try await silentRecording(store, frames: [2_400])
        let second = try await silentRecording(store, frames: [2_400])
        let controller = AudioController(store: store)
        var played: [UUID] = []
        let observation = controller.$playingRecordingID.compactMap { $0 }.sink { played.append($0) }
        defer { observation.cancel() }
        try await controller.play(recordingIDs: [first, second], playbackID: first)
        try await waitFor { controller.playingID == nil }
        #expect(played == [first, second])
        #expect(controller.state == .paused)
        await controller.shutdown(); try await store.close()
    }

    @MainActor @Test func deletionOfQueuedOriginalSkipsItAndReleasesItsLease() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-paragraph-delete-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let first = try await silentRecording(store, frames: [6_400])
        let deleted = try await silentRecording(store, frames: [8_000])
        let third = try await silentRecording(store, frames: [16_000])
        let controller = AudioController(store: store)
        var played: [UUID] = []
        let observation = controller.$playingRecordingID.compactMap { $0 }.sink { played.append($0) }
        defer { observation.cancel() }
        try await controller.play(recordingIDs: [first, deleted, third], playbackID: first)
        try await store.deleteAudio(recordingID: deleted)
        #expect(try await store.recording(id: deleted)?.audioState == .deletePending)
        try await waitFor { controller.playingRecordingID == third }
        #expect(played == [first, third])
        #expect(abs(controller.playbackDuration - 1.4) < 0.0001)
        #expect(controller.playbackNotice == "有 1 段原音已删除或不可用，已跳过")
        controller.stopPlayback(); await controller.shutdown()
        #expect(try await store.recording(id: deleted)?.audioState == .deleted)
        #expect(try await store.recording(id: deleted)?.text == "独立回听资料")
        try await store.close()
    }

    @MainActor @Test func switchingAndCancellingASeekCannotResumeTheOldParagraph() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-paragraph-switch-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let first = try await silentRecording(store, frames: [3_200])
        let second = try await silentRecording(store, frames: [8_000, 24_000])
        let controller = AudioController(store: store)
        try await controller.play(recordingIDs: [first, second], playbackID: first)
        try await controller.play(recordingID: second)
        try await Task.sleep(for: .milliseconds(350))
        #expect(controller.playingID == second && controller.playingRecordingID == second)
        controller.seekPlayback(to: 0.6)
        controller.stopPlayback()
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.playingID == nil && controller.playingRecordingID == nil)
        #expect(controller.playbackPosition == 0 && controller.playbackDuration == 0)
        await controller.shutdown()
        for id in [first, second] {
            try await store.deleteAudio(recordingID: id)
            #expect(try await store.recording(id: id)?.audioState == .deleted)
        }
        try await store.close()
    }

    @MainActor @Test func pauseDuringNextOriginalValidationCannotResumePlaybackOrCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-paragraph-pause-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let first = try await silentRecording(store, frames: [2_400])
        let second = try await silentRecording(store, frames: [16_000])
        let gate = PlaybackTransitionGate()
        let controller = AudioController(store: store, recognitionFactory: RecognitionSessionFactory(), playbackRecord: { id in
            if id == second { await gate.wait() }
            return try await store.recording(id: id)
        })
        var played: [UUID] = []
        let observation = controller.$playingRecordingID.compactMap { $0 }.sink { played.append($0) }
        defer { observation.cancel() }
        try await controller.play(recordingIDs: [first, second], playbackID: first)
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while await !gate.entered, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await gate.entered)
        await controller.pause()
        await gate.release()
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.playingID == nil && controller.playingRecordingID == nil)
        #expect(controller.state == .paused && controller.playbackDuration == 0)
        #expect(played == [first])
        await controller.shutdown()
        try await store.deleteAudio(recordingID: second)
        #expect(try await store.recording(id: second)?.audioState == .deleted)
        try await store.close()
    }

    @MainActor @Test func unreadableChunkDoesNotBlockTheNextOriginalAndAllMissingIsHonest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-paragraph-unreadable-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let damaged = try await silentRecording(store, frames: [8_000])
        let second = try await silentRecording(store, frames: [16_000])
        let chunk = try #require(try await store.audioChunks(recordingID: damaged).first)
        try Data("invalid synthetic WAV".utf8).write(to: await store.audioURL(for: chunk))
        let controller = AudioController(store: store)
        try await controller.play(recordingIDs: [damaged, second], playbackID: damaged)
        #expect(controller.playingID == damaged && controller.playingRecordingID == second)
        #expect(controller.playbackDuration == 1 && controller.playbackNotice != nil)
        controller.stopPlayback()
        try await store.deleteAudio(recordingID: second)
        do {
            try await controller.play(recordingIDs: [UUID(), second], playbackID: UUID())
            Issue.record("An entirely unavailable paragraph cannot claim playback")
        } catch { #expect(controller.playbackNotice == "有 2 段原音已删除或不可用，已跳过") }
        #expect(controller.playingID == nil && controller.state == .paused)
        await controller.shutdown(); try await store.close()
    }
}
