import Foundation

@testable import SaytileKit

// A pinned prefix represents already downloaded bytes. The missing suffix comes from
// the release URL used by Settings. Only this temporary library may be changed.
@main struct MandarinDownload {
  static func main() async throws {
    let args = CommandLine.arguments
    let files = FileManager.default
    let output = URL(fileURLWithPath: args[2])
    let root = files.temporaryDirectory.appending(path: "saytile-download-" + UUID().uuidString)
    defer { try? files.removeItem(at: root) }
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 35
    config.timeoutIntervalForResource = 70
    if let port = ProcessInfo.processInfo.environment["SAYTILE_TEST_PROXY_PORT"].flatMap(Int.init) {
      config.connectionProxyDictionary = [
        "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": port,
      ]
    }
    let library = LocalModelLibrary(root: root, session: URLSession(configuration: config))
    let id = LocalASRID.zipformer
    let m = try LocalModelManifest.load(id)
    let dir = await library.directory(m)
    let stage = dir.appendingPathExtension("partial")
    try files.createDirectory(at: stage, withIntermediateDirectories: true)
    let source = URL(fileURLWithPath: args[1])
    for f in m.files {
      let target = stage.appending(path: f.path)
      try files.copyItem(at: source.appending(path: f.path), to: target)
      guard try LocalModelLibrary.digest(target) == f.sha256 else {
        throw CocoaError(.fileReadCorruptFile)
      }
      if f.path == "model.int8.onnx" {
        let handle = try FileHandle(forWritingTo: target)
        try handle.truncate(atOffset: UInt64(f.bytes) - 8192)
        try handle.close()
      }
    }
    let partial = await library.status(id)
    guard !partial.installed, partial.bytes == m.size - 8192 else {
      throw CocoaError(.fileReadCorruptFile)
    }
    await library.download(id)
    await library.pause(id)
    let paused = await library.status(id)
    guard !paused.downloading, !paused.installed, paused.bytes == partial.bytes else {
      throw CocoaError(.fileReadUnknown)
    }
    await library.download(id)
    while await library.status(id).downloading { try await Task.sleep(for: .milliseconds(100)) }
    let done = await library.status(id)
    guard done.installed else {
      throw NSError(
        domain: "download", code: 1,
        userInfo: [NSLocalizedDescriptionKey: done.error ?? "not installed"])
    }
    let opened = try await library.validated(m)
    let modified = try opened.appending(path: "model.int8.onnx").resourceValues(forKeys: [
      .contentModificationDateKey
    ]).contentModificationDate
    let offline = URLSessionConfiguration.ephemeral
    offline.connectionProxyDictionary = [
      "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 1,
    ]
    let next = LocalModelLibrary(root: root, session: URLSession(configuration: offline))
    await next.download(id)
    while await next.status(id).downloading { try await Task.sleep(for: .milliseconds(80)) }
    let reopened = try await next.validated(m)
    guard
      try reopened.appending(path: "model.int8.onnx").resourceValues(forKeys: [
        .contentModificationDateKey
      ]).contentModificationDate == modified
    else { throw CocoaError(.fileWriteUnknown) }
    try await next.delete(id)
    let removed = await next.status(id)
    guard !removed.installed, removed.bytes == 0 else { throw CocoaError(.fileWriteUnknown) }
    let receipt: [String: Any] = [
      "status": "PASS", "revision": m.revision, "verified_total_bytes": m.size,
      "local_prefix_bytes": partial.bytes, "remote_suffix_bytes": 8192,
      "pause_retained_prefix": true, "offline_reopen_same_mtime": true,
      "delete_bytes": removed.bytes,
    ]
    try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
      .write(to: output)
  }
}
