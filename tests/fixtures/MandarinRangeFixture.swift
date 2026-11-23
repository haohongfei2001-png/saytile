import Foundation

@testable import SaytileKit

// Only the injected session sees these responses. The regular App uses URLSession.
private final class WeightFixture: URLProtocol, @unchecked Sendable {
  static let network = NSLock()
  nonisolated(unsafe) static var offline = true  // guarded by network
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}
  override func startLoading() {
    do {
      let args = CommandLine.arguments
      guard let url = request.url, url.host == "huggingface.co",
        let member = try LocalModelManifest.load(.zipformer).files.first(where: {
          $0.path == url.lastPathComponent
        }),
        let range = request.value(forHTTPHeaderField: "Range")?.dropFirst(6)
      else { throw URLError(.badURL) }
      let bounds = range.split(separator: "-").compactMap { Int64($0) }
      guard bounds.count == 2, bounds[0] >= 0, bounds[1] < member.bytes else {
        throw URLError(.badURL)
      }
      let source = URL(fileURLWithPath: args[1]).appending(path: member.path)
      let handle = try FileHandle(forReadingFrom: source)
      defer { try? handle.close() }
      let full = args[2] == "whole"
      let start = full ? 0 : bounds[0]
      let length = full ? member.bytes : bounds[1] - start + 1
      try handle.seek(toOffset: UInt64(start))
      if args[2] == "reconnect", start > 0, Self.network.withLock({ Self.offline }) {
        throw URLError(.notConnectedToInternet)
      }
      let echoed = (args[2] == "incorrect" && start > 0) ? start + 1 : start
      let reply = HTTPURLResponse(
        url: url, statusCode: full ? 200 : 206, httpVersion: "HTTP/1.1",
        headerFields: [
          "Content-Length": String(length),
          "Content-Range": "bytes \(echoed)-\(bounds[1])/\(member.bytes)",
        ])!
      client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
      var remaining = length
      while remaining > 0 {
        guard let piece = try handle.read(upToCount: min(262144, Int(remaining))), !piece.isEmpty
        else { throw URLError(.cannotDecodeRawData) }
        client?.urlProtocol(self, didLoad: piece)
        remaining -= Int64(piece.count)
      }
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
}

@main struct MandarinRangeFixture {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "saytile-controlled-range-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let mode = CommandLine.arguments[2]
    guard ["whole", "ranges", "incorrect", "reconnect"].contains(mode) else { exit(64) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WeightFixture.self]
    let library = LocalModelLibrary(root: root, session: URLSession(configuration: configuration))
    let manifest = try LocalModelManifest.load(.zipformer)
    await library.download(.zipformer)
    while await library.status(.zipformer).downloading {
      try await Task.sleep(for: .milliseconds(40))
    }
    if mode == "reconnect" {
      let interrupted = await library.status(.zipformer)
      guard !interrupted.installed, interrupted.error != nil, interrupted.bytes == 2 * 1024 * 1024 else {
        throw CocoaError(.fileReadCorruptFile)
      }
      WeightFixture.network.withLock { WeightFixture.offline = false }
      await library.download(.zipformer)
      while await library.status(.zipformer).downloading { try await Task.sleep(for: .milliseconds(40)) }
    }
    let result = await library.status(.zipformer)
    if mode == "incorrect" {
      guard !result.installed, result.error != nil, result.bytes == 2 * 1024 * 1024 else {
        throw CocoaError(.fileReadCorruptFile)
      }
    } else {
      guard result.installed, result.error == nil, result.bytes == manifest.size else {
        throw CocoaError(.fileReadCorruptFile)
      }
      let directory = try await library.validated(manifest)
      for f in manifest.files {
        guard try LocalModelLibrary.digest(directory.appending(path: f.path)) == f.sha256 else {
          throw CocoaError(.fileReadCorruptFile)
        }
      }
    }
    print("PASS", mode, "bytes", result.bytes, "installed", result.installed)
  }
}
