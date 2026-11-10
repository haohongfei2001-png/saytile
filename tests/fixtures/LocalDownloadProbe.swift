import Foundation
import SaytileKit

@main struct LocalDownloadProbe {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "saytile-download-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let config = URLSessionConfiguration.ephemeral
    if let port = ProcessInfo.processInfo.environment["SAYTILE_TEST_PROXY_PORT"].flatMap(Int.init) {
      config.connectionProxyDictionary = [
        "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": port,
      ]
    }
    let session =
      ProcessInfo.processInfo.environment["SAYTILE_TEST_PROXY_PORT"] == nil
      ? URLSession.shared : URLSession(configuration: config)
    let library = LocalModelLibrary(root: root, session: session)
    let requested = CommandLine.arguments.dropFirst().first ?? LocalASRID.sherpa.rawValue
    guard let id = LocalASRID(rawValue: requested), [.sherpa, .qwen, .zipformer].contains(id) else {
      exit(64)
    }
    let start = ProcessInfo.processInfo.systemUptime
    await library.download(id)
    var paused: Int64 = 0
    var resumedAfterTransportError = false
    var lastProgress = start
    var observedBytes: Int64 = 0
    while true {
      try await Task.sleep(for: .milliseconds(150))
      let status = await library.status(id)
      if status.bytes > observedBytes {
        lastProgress = ProcessInfo.processInfo.systemUptime
        if status.bytes / (16*1024*1024) > observedBytes / (16*1024*1024) {
          FileHandle.standardError.write(Data("downloaded_bytes=\(status.bytes)\n".utf8))
        }
        observedBytes = status.bytes
      }
      if let error = status.error {
        print(
          "DOWNLOAD_ERROR partial_bytes=\(status.bytes) installed=\(status.installed) message=\(error)"
        )
        guard !resumedAfterTransportError, !status.installed else {
          throw AudioFailure.message(error)
        }
        resumedAfterTransportError = true
        await library.download(id)
        continue
      }
      if !status.downloading { break }
      if paused == 0, status.bytes > 0, status.bytes < status.total {
        await library.pause(id)
        let checkpoint = await library.status(id)
        guard !checkpoint.installed, !checkpoint.downloading else {
          throw CocoaError(.fileReadCorruptFile)
        }
        paused = checkpoint.bytes
        await library.download(id)
      }
      let now = ProcessInfo.processInfo.systemUptime
      if now - lastProgress > 300 || now - start > 3600 { throw URLError(.timedOut) }
    }
    let done = await library.status(id)
    guard done.installed, paused > 0, done.total == done.bytes else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let reopened = LocalModelLibrary(root: root)
    let afterUpgrade = await reopened.status(id)
    guard afterUpgrade.installed else { throw CocoaError(.fileReadCorruptFile) }
    try await reopened.delete(id)
    let removed = await reopened.status(id)
    guard !removed.installed, removed.bytes == 0 else { throw CocoaError(.fileWriteUnknown) }
    print(
      "PASS paused_bytes=\(paused) verified_bytes=\(done.bytes) delete=true reopen=true transport_retry=\(resumedAfterTransportError) seconds=\(ProcessInfo.processInfo.systemUptime-start)"
    )
  }
}
