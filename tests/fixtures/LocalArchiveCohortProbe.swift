import Foundation
import SaytileKit

/// Test driver for the actual per-record archive action. A terminal no-result on
/// one VAD record must not prevent independent records from being requested.
@main struct LocalArchiveCohortProbe {
    @MainActor static func main() async {
        do { try await run() } catch { print("archive fixture: " + error.localizedDescription); exit(2) }
    }
    @MainActor static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 6 else { throw CocoaError(.fileNoSuchFile) }
        let job = args[1], root = URL(fileURLWithPath: args[2]), weights = URL(fileURLWithPath: args[3]), app = URL(fileURLWithPath: args[4])
        guard root.pathComponents.contains(where: { $0.hasPrefix("saytile-local-batch-") }),
              let sha = Bundle(url: app)?.object(forInfoDictionaryKey: "SaytileSourceRevision") as? String,
              FileManager.default.changeCurrentDirectoryPath(app.appending(path: "Contents/Resources").path) else { throw CocoaError(.fileReadNoPermission) }
        let store = try SaytileStore(directory: root)
        let controller = AudioController(store: store, startupRecoveryReady: false)
        let service = LocalASRService(root: weights, helpers: app.appending(path: "Contents/Helpers"))
        if job == "record" {
            guard try await store.listRecordings(limit: 1).isEmpty else { throw CocoaError(.fileWriteFileExists) }
            _ = try await controller.replayLocalFixture(root.appending(path: "fixture.wav"), recordOnly: true)
        } else {
            guard let id = LocalASRID(rawValue: job), (id.capability == .batch || id == .qwen) else { throw CocoaError(.fileReadCorruptFile) }
            controller.selectLocalModels(live: .sherpa, archive: id, service: service)
            let records = try await store.listRecordings(limit: 40)
            if id == .qwen {
                guard records.count == 1, records[0].recognitionState == .failed else { throw CocoaError(.fileReadCorruptFile) }
            } else {
                guard records.count >= 10, records.count < 40, records.allSatisfy({ $0.recognitionState == .queued && $0.text.isEmpty }) else { throw CocoaError(.fileReadCorruptFile) }
            }
            var result = [[String: Any]]()
            for r in records.reversed() {
                let started = ProcessInfo.processInfo.systemUptime
                await controller.retry(recordingID: r.id)
                while true {
                    try await Task.sleep(for: .milliseconds(60))
                    guard let current = try await store.recording(id: r.id), ProcessInfo.processInfo.systemUptime - started < 190 else { throw CocoaError(.fileReadUnknown) }
                    if [.failed,.completed].contains(current.recognitionState) && controller.reprocessingID == nil {
                        let providers = try await store.modelRuns(recordingID: r.id).map { $0.ticket.provider }
                        guard current.audioState == .available, Set(providers).isSubset(of: [job]),
                              current.recognitionState != .completed || (providers == [job] && !current.text.isEmpty) else { throw CocoaError(.fileReadCorruptFile) }
                        let frames = try await store.audioChunks(recordingID: r.id).reduce(0) { $0 + $1.frames }
                        result.append(["state":current.recognitionState.rawValue,"frames":frames,"text":current.text,"providers":providers,"elapsed_s":ProcessInfo.processInfo.systemUptime-started,"issue":current.lastError ?? ""])
                        break
                    }
                }
            }
            let output: [String: Any] = ["source":sha,"model":job,"rows":result]
            try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: args[5]))
        }
        await controller.shutdown()
        await service.releaseIdle()
    }
}
