import AppKit
import SaytileKit

@main struct CopyProbe {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let suite = "app.saytile.test.copy." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-copy-" + UUID().uuidString)
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        var config = RecognitionConfiguration()
        config.automaticRecovery = false
        try config.save(to: preferences)
        var starts = 0, pauses = 0
        let capture = AppCaptureDependencies(state: { _ in .listening }, start: { _ in starts += 1 }, pause: { _ in pauses += 1 }, level: { _ in 0 })
        let connection = AppConnectionDependencies(presence: { _ in .missing }, save: { _, _ in }, delete: { _ in }, verify: { _, _ in throw CancellationError() }, applyConfiguration: { _, _ in }, revokeCloud: { _ in })
        let model = try AppModel(directory: directory, preferences: preferences, connectionDependencies: connection, captureDependencies: capture, copyPasteboard: board)
        await model.initialLoad()
        let selected = "cafe\u{301} 😀"
        let records = ["请保留 \(selected) 的原文。", "不要支付15元。"]
        for text in records {
            let row = try await model.store.createRecording()
            _ = try await model.store.saveEdit(recordingID: row.id, text: text)
            try await model.store.finishRecording(id: row.id)
        }
        await model.refresh()
        let label = model.panelCaptureLabel
        var generation = board.changeCount
        model.copy(selected)
        precondition(board.changeCount > generation && board.string(forType: .string)?.utf16.elementsEqual(selected.utf16) == true)
        generation = board.changeCount
        model.copyRecent()
        precondition(board.changeCount > generation && board.string(forType: .string)?.utf16.elementsEqual(records.joined(separator: "\n").utf16) == true)
        precondition(starts == 0 && pauses == 0 && model.panelCaptureLabel == label && model.audio.state == .paused)
        print("PRIVATE_PASTEBOARD_MODEL_PASS selected_exact_utf16=true full_two_records_exact_utf16=true capture_actions=0 actual_audio_paused=true")
        await model.prepareForExit()
    }
}
