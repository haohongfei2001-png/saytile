import AppKit
import CryptoKit
import Darwin
import Foundation
import SaytileKit

/// Run under a macOS profile denying network sockets. The input is a public test WAV.
/// Exercising offline routing and journaling here never runs a second ASR beside the benchmark.
@main
struct OfflineLocalModelProbe {
    enum Failure: Error { case invalid(String) }

    static func check(_ flag: Bool, _ detail: String) throws {
        if !flag { throw Failure.invalid(detail) }
    }

    static func networkConnectError() -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        if fd < 0 { return errno }
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        address.sin_port = UInt16(9).bigEndian
        let rc = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return rc == 0 ? 0 : errno
    }

    static func hash(_ file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 5 else { throw Failure.invalid("Expected isolated root, fixture, weights and output") }
        let root = URL(fileURLWithPath: args[1]), fixture = URL(fileURLWithPath: args[2])
        let source = URL(fileURLWithPath: args[3]), output = URL(fileURLWithPath: args[4])
        let fm = FileManager.default, id = LocalASRID.qwen
        try check(root.path.hasPrefix("/private/tmp/saytile-network-denied-")
                  && (try fm.contentsOfDirectory(atPath: root.path)).isEmpty, "not a fresh temporary directory")
        let socketError = networkConnectError()
        try check(socketError == EPERM || socketError == EACCES, "outbound networking was not denied by the OS")
        let suite = "app.saytile.offline-test." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let data = root.appending(path: "Archive")
        let model = try AppModel(directory: data, preferences: prefs)
        try check(model.deviceOnly && !model.hosted.consent && !model.usesBYOK, "unexpected network route at first launch")
        model.selectLocal(id)
        let start = ProcessInfo.processInfo.systemUptime
        await model.refreshLocalRecommendation()
        let routeSeconds = ProcessInfo.processInfo.systemUptime - start
        let appleReady = await model.localModels.availability(.apple).installed
        try check(model.manualLocalModel == id && model.selectedLocalModel == .apple && model.deviceOnly
                  && !model.localTextAllowed && !model.usesBYOK && !model.hosted.consent && !model.hosted.selected,
                  "manual model changed local privacy or selected the missing helper")
        let library = model.localModels.library
        let before = await library.status(id)
        try check(!before.installed && before.bytes == 0 && !before.downloading, "initial model cache not empty")
        guard let task = await library.download(id) else { throw Failure.invalid("missing download job") }
        // If the system language is also absent, exercise the normal Apple error path.
        // With an installed asset, keep this recovery check free of competing inference.
        _ = try await model.audio.replayLocalFixture(fixture, recordOnly: appleReady)
        await task.value
        let rejected = await library.status(id)
        try check(!rejected.installed && rejected.error != nil && !rejected.downloading, "denied download promoted an install")
        let recordings = try await model.store.listRecordings(limit: 10)
        guard recordings.count == 1, let captured = recordings.first, captured.audioState == .available
        else { throw Failure.invalid("recording did not survive the download failure") }
        let chunks = try await model.store.audioChunks(recordingID: captured.id)
        try check(chunks.count == 1 && chunks[0].frames > 0, "missing durable single-chunk PCM")
        let original = try await model.store.audioURL(for: chunks[0])
        let pcm = try hash(original)
        let edit = try await model.store.saveEdit(recordingID: captured.id, text: "离线原音独立保存。")
        let runs = try await model.store.modelRuns(recordingID: captured.id)
        if appleReady {
            try check(runs.isEmpty, "record-only capture dispatched a recognizer")
        } else {
            try check(runs.map(\.ticket.provider) == ["apple-speech-analyzer"]
                      && captured.recognitionState == .failed && captured.text.isEmpty && captured.lastError != nil,
                      "unavailable Apple did not leave a recoverable on-device failure")
        }
        await model.prepareForExit()
        let reopened = try SaytileStore(directory: data)
        try check(try await reopened.revisions(recordingID: captured.id).contains { $0.id == edit.id && $0.text == "离线原音独立保存。" }
                  && (try hash(original)) == pcm, "reopening lost the audio or local edit")
        try await reopened.close()

        // Start a fresh library from real pinned bytes at a nonzero offset.
        let m = try LocalModelManifest.load(id), stageRoot = root.appending(path: "Interrupted")
        let installed = stageRoot.appending(path: id.rawValue).appending(path: m.revision)
        let stage = installed.appendingPathExtension("partial")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        let small = source.appending(path: m.revision).appending(path: "config.json")
        let prefix = try Data(contentsOf: small).prefix(2048)
        let saved = stage.appending(path: "config.json")
        try Data(prefix).write(to: saved)
        let checksum = try hash(saved)
        let interrupted = LocalModelLibrary(root: stageRoot)
        guard let resume = await interrupted.download(id) else { throw Failure.invalid("no resume attempt") }
        await resume.value
        let resumed = await LocalModelLibrary(root: stageRoot).status(id)
        try check(!resumed.installed && resumed.bytes == Int64(prefix.count) && (try hash(saved)) == checksum,
                  "offset or partial digest changed after denied resume")
        // Read an existing pinned cache without copying or editing any user files.
        let cached = LocalModelLibrary(root: source.deletingLastPathComponent())
        let cache = await cached.status(id)
        try check(cache.installed && cache.bytes == m.size && !cache.downloading, "existing cache did not verify offline")

        let receipt: [String: Any] = [
            "network_connect_errno": socketError, "empty_cache_fallback": model.selectedLocalModel.rawValue,
            "apple_language_asset_ready_for_this_probe_identity": appleReady, "first_launch_local": true,
            "requested_missing_model": id.rawValue, "route_decision_seconds": routeSeconds, "model_download_error": rejected.error ?? "",
            "hosted_audio_consent": model.hosted.consent, "byok_active": model.usesBYOK, "local_text_cloud_consent": model.localTextAllowed,
            "journal_frames": chunks.reduce(0) { $0 + $1.frames }, "journal_sha256": pcm,
            "reopened_user_revision_intact": true, "failed_to_promote_incomplete_model": true,
            "checkpoint_bytes_before_and_after": resumed.bytes, "checkpoint_sha256": checksum, "existing_cache_verified_bytes": cache.bytes,
            "public_fixture_sha256": try hash(fixture), "attempted_providers": runs.map(\.ticket.provider),
            "capture_recognition_state": captured.recognitionState.rawValue, "capture_error": captured.lastError ?? ""
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted,.sortedKeys]).write(to: output, options: .atomic)
    }
}
