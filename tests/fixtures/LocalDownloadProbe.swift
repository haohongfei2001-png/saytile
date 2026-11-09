import Foundation
import SaytileKit

@main struct LocalDownloadProbe {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "saytile-download-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LocalModelLibrary(root: root)
        let id = LocalASRID.sherpa
        let start = ProcessInfo.processInfo.systemUptime
        await library.download(id)
        var paused: Int64 = 0
        while true {
            try await Task.sleep(for: .milliseconds(150))
            let status = await library.status(id)
            if let error = status.error { throw AudioFailure.message(error) }
            if !status.downloading { break }
            if paused == 0, status.bytes > 0, status.bytes < status.total {
                await library.pause(id)
                let checkpoint = await library.status(id)
                guard !checkpoint.installed, !checkpoint.downloading else { throw CocoaError(.fileReadCorruptFile) }
                paused = checkpoint.bytes
                await library.download(id)
            }
            if ProcessInfo.processInfo.systemUptime - start > 260 { throw URLError(.timedOut) }
        }
        let done = await library.status(id)
        guard done.installed, paused > 0, done.total == done.bytes else { throw CocoaError(.fileReadCorruptFile) }
        let reopened = LocalModelLibrary(root: root)
        let afterUpgrade = await reopened.status(id)
        guard afterUpgrade.installed else { throw CocoaError(.fileReadCorruptFile) }
        try await reopened.delete(id)
        let removed = await reopened.status(id)
        guard !removed.installed, removed.bytes == 0 else { throw CocoaError(.fileWriteUnknown) }
        print("PASS paused_bytes=\(paused) verified_bytes=\(done.bytes) delete=true reopen=true seconds=\(ProcessInfo.processInfo.systemUptime-start)")
    }
}
