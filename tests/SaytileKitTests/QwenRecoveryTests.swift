import Foundation
import Testing
@testable import SaytileKit

@Suite("Local model preview and download recovery")
struct QwenRecoveryTests {
    // Verbatim partials from the pinned Qwen worker on public FLEURS sample 9eb2d543a0a36152.
    private let original = [
        "嗯。", "致力首選燈。", "致力首选登山目的地。科", "致力首选登山目的地——喀嚓莫山。",
        "致力首选登山目的地——喀察莫山谷，被称为。", "致力首选登山目的地——科查莫山谷，被称为南美洲的优。"
    ]

    @Test func longPreviewResumesAfterTwoAlignedCorrectionsFromTheDecoder() {
        var preview = LocalLiveText(model: .qwen)
        for words in original { #expect(preview.accept(words, final: false) == 0) }
        let corrected = "智利首选登山目的地科查莫山谷，被称为南美洲的优美圣地。"
        #expect(preview.accept(corrected, final: false) == nil)
        #expect(preview.previous == original.last)
        for words in [corrected + "这里有各", corrected + "这里有各式各样的花岗岩。",
                      corrected + "这里有各式各样的花岗岩大石壁和峭。"] {
            #expect(preview.accept(words, final: false) == 0)
            #expect(preview.previous == words)
        }
        let final = corrected + "这里有各式各样的花岗岩大石壁和峭壁。"
        #expect(preview.accept(final, final: true) == final.utf16.count)
    }

    @Test func longPreviewRejectsWidelyChangedPassesDespiteSharedWords() {
        var preview = LocalLiveText(model: .qwen)
        for words in original { #expect(preview.accept(words, final: false) == 0) }
        let unrelated = "智利首选登山目的地实际上完全换到了另一座机场附近的博物馆准备售票。"
        #expect(preview.accept(unrelated, final: false) == nil)
        #expect(preview.accept(unrelated + "下一次会继续。", final: false) == nil)
        #expect(preview.previous == original.last)
    }

    private func fixture(_ variant: String) throws -> LocalModelManifest {
        let revision = try LocalModelManifest.load(.qwen).revision
        let file = LocalModelManifest.File(path: "weights", bytes: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        return LocalModelManifest(id: .qwen, repo: "fixture/" + variant, revision: revision, license: "fixture", files: [file])
    }

    @Test func coldReopenVerifiesEqualSizeDamageAndReportsAllRemovableBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LocalModelLibrary(root: root)
        let manifest = try fixture("valid")
        let dir = await library.directory(manifest), stage = dir.appendingPathExtension("partial")
        for folder in [dir, stage] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let weights = dir.appending(path: "weights")
        try Data("abd".utf8).write(to: weights)
        try Data("a".utf8).write(to: stage.appending(path: "weights"))
        let damaged = await library.status(manifest)
        #expect(!damaged.installed && damaged.error != nil && damaged.bytes == 1 && damaged.diskBytes == 4)
        await #expect(throws: (any Error).self) { try await library.validated(manifest) }
        try Data("abc".utf8).write(to: weights, options: .atomic)
        let repaired = await library.status(manifest)
        #expect(repaired.installed && repaired.error == nil && repaired.bytes == 3 && repaired.diskBytes == 4)
        let reopened = await LocalModelLibrary(root: root).status(manifest)
        #expect(reopened.installed && reopened.error == nil)
        try await library.delete(.qwen)
        let removed = await library.status(manifest)
        #expect(!removed.installed && removed.diskBytes == 0 && removed.error == nil)
    }

    @Test func invalidCompleteResponsePreservesCheckpointForNextDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WholeWeightResponse.self]
        let library = LocalModelLibrary(root: root, session: URLSession(configuration: config))
        let bad = try fixture("invalid"), good = try fixture("valid")
        let stage = await library.directory(bad).appendingPathExtension("partial")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let checkpoint = stage.appending(path: "weights")
        try Data("a".utf8).write(to: checkpoint)
        await #expect(throws: (any Error).self) { try await library.install(bad) }
        #expect(try Data(contentsOf: checkpoint) == Data("a".utf8))
        let interrupted = await library.status(bad)
        #expect(!interrupted.installed && interrupted.bytes == 1 && interrupted.diskBytes == 1)
        try await library.install(good)
        let result = await library.status(good)
        #expect(result.installed && result.bytes == 3 && result.diskBytes == 3)
        let dir = try await library.validated(good)
        #expect(try Data(contentsOf: dir.appending(path: "weights")) == Data("abc".utf8))
    }
}

private final class WholeWeightResponse: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "3"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((url.pathComponents.contains("invalid") ? "abd" : "abc").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
