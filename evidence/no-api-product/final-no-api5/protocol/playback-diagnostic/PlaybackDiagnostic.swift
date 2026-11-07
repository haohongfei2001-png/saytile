import AppKit
import Combine
import Darwin
import Foundation
@testable import SaytileKit

@main
struct PlaybackDiagnostic {
    enum Failure: Error { case missingPositiveEvent, incorrectSeekOrLease }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-playback-timing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        for frames in [16_000, 9_600] {
            try journal.openChunk()
            try journal.append(Data(repeating: 0, count: frames * 2))
            try journal.closeChunk()
            try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: Int64(frames))
        }
        try await store.finishRecording(id: record.id)
        try await store.saveEdit(recordingID: record.id, text: "静音播放隔离样例")
        let controller = AudioController(store: store, startupRecoveryReady: false)
        let baseline = ProcessInfo.processInfo.systemUptime
        func elapsed() -> Double { ProcessInfo.processInfo.systemUptime - baseline }
        var firstPositive: (time: Double, position: Double)?
        let progress = controller.$playbackPosition.sink { value in
            if value > 0 && firstPositive == nil {
                firstPositive = (elapsed(), value)
                print("FIRST_REAL_PROGRESS time=\(elapsed()) position=\(value)")
            }
        }
        // Deterministic counterexample to sampling exactly once after 180 ms.
        // Enqueue one synthetic MainActor occupancy before the normal playback
        // progress task is created. The production player, timer and source stay original.
        let scheduling = controller.$playingID.compactMap { $0 }.first().sink { _ in
            Task { @MainActor in
                print("CONTROLLED_MAIN_ACTOR_OCCUPANCY_START time=\(elapsed())")
                usleep(220_000)
                print("CONTROLLED_MAIN_ACTOR_OCCUPANCY_END time=\(elapsed())")
            }
        }
        defer { progress.cancel(); scheduling.cancel() }
        try await controller.play(recordingID: record.id)
        print("PLAY_RETURN time=\(elapsed()) active=\(controller.playingID == record.id) duration=\(controller.playbackDuration)")
        try await Task.sleep(for: .milliseconds(180))
        print("ORIGINAL_SINGLE_SAMPLE time=\(elapsed()) position=\(controller.playbackPosition) active=\(controller.playingID == record.id)")
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while firstPositive == nil && controller.playingID == record.id && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let firstPositive, firstPositive.position > 0, controller.playingID == record.id else { throw Failure.missingPositiveEvent }
        controller.seekPlayback(to: 1.15)
        guard abs(controller.playbackPosition - 1.15) < 0.0001 else { throw Failure.incorrectSeekOrLease }
        controller.seekPlayback(to: 0.1)
        guard abs(controller.playbackPosition - 0.1) < 0.0001 else { throw Failure.incorrectSeekOrLease }
        try await store.deleteAudio(recordingID: record.id)
        guard try await store.recording(id: record.id)?.audioState == .deletePending else { throw Failure.incorrectSeekOrLease }
        controller.stopPlayback(); await controller.shutdown()
        guard controller.state == .paused, try await store.recording(id: record.id)?.audioState == .deleted,
              try await store.recording(id: record.id)?.text == "静音播放隔离样例" else { throw Failure.incorrectSeekOrLease }
        try await store.close()
        print("BOUNDED_EVENT_SEEK_LEASE_PASS first_time=\(firstPositive.time) first_position=\(firstPositive.position) actual_player=true synthetic_silence=true microphone_opened=false")
    }
}
