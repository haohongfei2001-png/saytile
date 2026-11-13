import Foundation
import CryptoKit

public enum LocalASRCapability: String, Sendable { case streaming, chunked, batch }

public enum LocalASRID: String, CaseIterable, Codable, Sendable {
    case apple, sherpa, nemotron = "nemotron-metal", qwen = "qwen-small", paraformer, sensevoice, qwenLarge = "qwen-large", zipformer
    /// Append new IDs to preserve persisted evidence UUIDs. Weights without an explicit commercial grant remain research-only.
    public static let consumer: [Self] = [.apple, .sherpa, .qwen]
    public var sherpaRuntime: Bool { self == .sherpa || self == .zipformer }
    public var title: String {
        switch self {
        case .zipformer: "Streaming Zipformer CTC INT8"
        case .apple: "Apple SpeechAnalyzer"
        case .sherpa: "Streaming Paraformer INT8"
        case .nemotron: "Nemotron 3.5 Streaming · Metal"
        case .qwen: "Qwen3-ASR 0.6B · MLX 4-bit"
        case .paraformer: "FluidAudio Paraformer Large INT8"
        case .sensevoice: "FluidAudio SenseVoice Small INT8"
        case .qwenLarge: "Qwen3-ASR 1.7B · MLX 4-bit"
        }
    }
    public var capability: LocalASRCapability {
        switch self {
        case .apple, .sherpa, .nemotron, .zipformer: .streaming
        case .qwen, .qwenLarge: .chunked
        case .paraformer, .sensevoice: .batch
        }
    }
    var evidenceID: UUID {
        let index = Self.allCases.firstIndex(of: self)!
        return UUID(uuidString: String(format: "A71E0001-0000-4000-8000-%012d", 8 + index))!
    }
}

private final class LocalResourceAnchor {}

public struct LocalModelManifest: Decodable, Sendable {
    public struct File: Decodable, Sendable {
        public let path: String
        public let bytes: Int64
        public let sha256: String
    }
    public let id: LocalASRID
    public let repo: String
    public let revision: String
    public let license: String
    public let files: [File]
    public var size: Int64 { files.reduce(0) { $0 + $1.bytes } }

    public static func load(_ id: LocalASRID) throws -> Self {
        // Standalone signed applications copy the catalog into Contents/Resources.
        var bundles = [Bundle.main]
        if Bundle.main.bundleURL.pathExtension != "app" {
            // SwiftPM tests, tools and static-library clients may have the resource
            // bundle next to either the executable or the test bundle. An absent
            // optional catalog must be reportable without a Bundle.module trap.
            let anchor = Bundle(for: LocalResourceAnchor.self)
            let roots = [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent(),
                         anchor.resourceURL, anchor.bundleURL.deletingLastPathComponent()]
            for root in roots.compactMap({ $0 }) {
                if let bundle = Bundle(url: root.appending(path: "Saytile_SaytileKit.bundle")) { bundles.append(bundle) }
            }
        }
        let url = bundles.lazy.compactMap { $0.url(forResource: id.rawValue, withExtension: "json", subdirectory: "LocalASR") }.first
        guard let url else { throw AudioFailure.message("当前版本缺少模型清单") }
        let model = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard model.id == id, model.revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              model.repo.split(separator: "/").count == 2, !model.files.isEmpty,
              Set(model.files.map(\.path)).count == model.files.count,
              model.files.allSatisfy({ $0.bytes > 0 && $0.sha256.count == 64 && !$0.path.hasPrefix("/")
                    && !$0.path.split(separator: "/").contains("..") }) else { throw AudioFailure.message("模型清单无效") }
        return model
    }
}

public struct LocalModelStatus: Sendable, Equatable {
    public let bytes: Int64
    public let total: Int64
    /// Includes a previous, damaged installation while its replacement downloads.
    public let diskBytes: Int64
    public let installed: Bool
    public let downloading: Bool
    public let error: String?
}

/// Pinned weights only. Nothing in a partial directory is visible to a recognizer.
public actor LocalModelLibrary {
    private let root: URL
    private let http: URLSession
    private var jobs: [LocalASRID: Task<Void, Never>] = [:]
    private var errors: [LocalASRID: String] = [:]
    private var deleting: Set<LocalASRID> = []
    private struct Verification {
        let revision: String
        let stamps: [Date]
        let result: Task<Bool, Error>
    }
    private var verification: [LocalASRID: Verification] = [:]
    private let fm = FileManager.default
    public init(root: URL, session: URLSession? = nil) {
        self.root = root
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 90
        self.http = session ?? URLSession(configuration: config)
    }
    static func checkDownloadCapacity(remaining: Int64, available: Int64) throws {
        // Reserve room for concurrent temporary ranges and the capture journal.
        guard available >= remaining + 128_000_000 else {
            throw AudioFailure.message("磁盘空间不足。请释放空间后继续下载，或选用系统识别。")
        }
    }
    func directory(_ m: LocalModelManifest) -> URL {
        root.appending(path: m.id.rawValue).appending(path: m.revision, directoryHint: .isDirectory)
    }
    private func staging(_ m: LocalModelManifest) -> URL { directory(m).appendingPathExtension("partial") }
    private func stamps(_ m: LocalModelManifest, _ dir: URL) throws -> [Date] {
        try m.files.map { f in
            let v = try dir.appending(path: f.path).resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey,.attributeModificationDateKey])
            guard v.isRegularFile == true, v.isSymbolicLink != true, Int64(v.fileSize ?? -1) == f.bytes,
                  let changed = v.attributeModificationDate else { throw AudioFailure.message("模型文件不完整") }
            return changed
        }
    }
    static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var sha = SHA256()
        // Foundation's file reads can retain autoreleased NSData until the actor
        // returns. Bound the read lifetime even when verifying a large model.
        var hasMore = true
        while hasMore {
            try Task.checkCancellation()
            hasMore = try autoreleasepool {
                guard let part = try file.read(upToCount: 1024 * 1024), !part.isEmpty else { return false }
                sha.update(data: part)
                return true
            }
        }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func validated(_ m: LocalModelManifest) async throws -> URL {
        guard !deleting.contains(m.id) else { throw CancellationError() }
        let dir = directory(m), current = try stamps(m, dir)
        let result: Task<Bool, Error>
        if let cached = verification[m.id], cached.revision == m.revision, cached.stamps == current {
            result = cached.result
        } else {
            verification[m.id]?.result.cancel()
            result = Task.detached(priority: .utility) {
                for file in m.files where try Self.digest(dir.appending(path: file.path)) != file.sha256 {
                    return false
                }
                return true
            }
            verification[m.id] = Verification(revision: m.revision, stamps: current, result: result)
        }
        // Settings, route selection and recognition share the same check. This
        // also caches failures until the on-disk files change or are removed.
        guard try await result.value, !deleting.contains(m.id), try stamps(m, dir) == current
        else { throw AudioFailure.message("模型校验失败，请重新下载") }
        return dir
    }
    public func status(_ id: LocalASRID) async -> LocalModelStatus {
        guard let m = try? LocalModelManifest.load(id) else {
            return .init(bytes: 0, total: 0, diskBytes: 0, installed: false, downloading: false, error: "模型清单不可用")
        }
        return await status(m)
    }
    func status(_ m: LocalModelManifest) async -> LocalModelStatus {
        let dir = directory(m), stage = staging(m)
        let installed = fm.fileExists(atPath: dir.path) ? (try? await validated(m)) != nil : false
        func fileBytes(in directory: URL) -> Int64 {
            guard fm.fileExists(atPath: directory.path) else { return 0 }
            return m.files.reduce(0) { total, file in
                let info = try? directory.appending(path: file.path).resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                return total + (info?.isRegularFile == true ? Int64(info?.fileSize ?? 0) : 0)
            }
        }
        let staged = fileBytes(in: stage)
        let stored = installed ? m.size : fileBytes(in: dir)
        let downloading = jobs[m.id] != nil
        let damaged = !installed && !downloading && !deleting.contains(m.id) && fm.fileExists(atPath: dir.path)
        return .init(bytes: installed ? m.size : staged, total: m.size, diskBytes: stored + staged,
                     installed: installed, downloading: downloading,
                     error: installed ? nil : errors[m.id] ?? (damaged ? "本机模型文件不完整或校验失败，请重新下载" : nil))
    }
    /// Historical research models can only be removed from Settings. Listing
    /// those controls must not start hashing gigabytes of unused weights.
    public func cachedExperimentalModels() -> [LocalASRID] {
        LocalASRID.allCases.filter { id in
            guard !LocalASRID.consumer.contains(id), let m = try? LocalModelManifest.load(id) else { return false }
            return fm.fileExists(atPath: directory(m).path) || fm.fileExists(atPath: staging(m).path)
        }
    }
    public func download(_ id: LocalASRID) {
        guard id != .apple, !deleting.contains(id), jobs[id] == nil else { return }
        errors[id] = nil
        jobs[id] = Task {
            do { try await install(try LocalModelManifest.load(id)) }
            catch {
                if !Task.isCancelled {
                    errors[id] = error is URLError ? "模型下载中断。可继续下载，或使用系统识别。" : error.localizedDescription
                }
            }
            jobs[id] = nil
        }
    }
    public func pause(_ id: LocalASRID) async {
        guard let task = jobs[id] else { return }
        task.cancel()
        await task.value
    }
    public func delete(_ id: LocalASRID) async throws {
        guard deleting.insert(id).inserted else { return }
        defer { deleting.remove(id) }
        verification.removeValue(forKey: id)?.result.cancel()
        await pause(id)
        let model = try LocalModelManifest.load(id)
        for path in [directory(model), staging(model)] where fm.fileExists(atPath: path.path) {
            try fm.removeItem(at: path)
        }
        errors[id] = nil
    }
    func install(_ m: LocalModelManifest) async throws {
        let dir = directory(m), stage = staging(m)
        if (try? await validated(m)) != nil { return }
        try Task.checkCancellation()
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        let available = try fm.attributesOfFileSystem(forPath: stage.path)[.systemFreeSize] as? NSNumber
        if let available {
            let pending = m.files.reduce(Int64(0)) { sum, file in
                let existing = (try? stage.appending(path: file.path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sum + max(0, file.bytes - Int64(existing))
            }
            try Self.checkDownloadCapacity(remaining: pending, available: available.int64Value)
        }
        for f in m.files {
            let target = stage.appending(path: f.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: target.path) { guard fm.createFile(atPath: target.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) } }
            let source = URL(string: "https://huggingface.co")!.appending(path: m.repo + "/resolve/" + m.revision + "/" + f.path)
            try await fetch(source, to: target, file: f)
        }
        try Task.checkCancellation()
        _ = try stamps(m, stage)
        // A failed repair never replaces a working model. Promotion is on the same volume.
        if fm.fileExists(atPath: dir.path) { _ = try fm.replaceItemAt(dir, withItemAt: stage) }
        else { try fm.moveItem(at: stage, to: dir) }
        verification[m.id] = Verification(revision: m.revision, stamps: try stamps(m, dir), result: Task { true })
        errors[m.id] = nil
    }
    private final class DownloadPart: Sendable {
        let offset: Int64
        let url: URL
        let wholeFile: Bool
        init(offset: Int64, url: URL, wholeFile: Bool) {
            self.offset = offset; self.url = url; self.wholeFile = wholeFile
        }
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    private static func requestPart(_ url: URL, offset: Int64, end: Int64, total: Int64, session: URLSession) async throws -> DownloadPart {
        // Some CDNs cache the redirect to a signed byte range. Give different
        // ranges different cache keys while keeping the immutable source revision.
        for attempt in 0...1 {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            parts.queryItems = [URLQueryItem(name: "download", value: "true"),
                                URLQueryItem(name: "range", value: "\(offset)-\(end)"),
                                URLQueryItem(name: "attempt", value: String(attempt))]
            var request = URLRequest(url: parts.url!)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
            do {
                let (file, reply) = try await session.download(for: request)
                do {
                    try Task.checkCancellation()
                    guard let response = reply as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    let size = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1)
                    let whole = response.statusCode == 200 && size == total
                    guard whole || (response.statusCode == 206 && size == end - offset + 1 &&
                        response.value(forHTTPHeaderField: "Content-Range") == "bytes \(offset)-\(end)/\(total)") else {
                        throw URLError(.badServerResponse)
                    }
                    return DownloadPart(offset: offset, url: file, wholeFile: whole)
                } catch {
                    try? FileManager.default.removeItem(at: file)
                    throw error
                }
            } catch {
                try Task.checkCancellation()
                guard attempt == 0, let issue = error as? URLError,
                      [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(issue.code) else { throw error }
            }
        }
        throw URLError(.timedOut)
    }

    private func fetch(_ url: URL, to target: URL, file: LocalModelManifest.File) async throws {
        let bytes = file.bytes
        let out = try FileHandle(forWritingTo: target)
        defer { try? out.close() }
        var start = Int64(try out.seekToEnd())
        if start > bytes { try out.truncate(atOffset: 0); start = 0 }
        let stride: Int64 = 2 * 1024 * 1024
        var acceptsRanges = false
        var verifiedWhole = false
        while start < bytes {
            try Task.checkCancellation()
            let offset = start
            let batchEnd = min(bytes, offset + stride * (acceptsRanges ? 4 : 1))
            let transport = http
            try await withThrowingTaskGroup(of: DownloadPart.self) { group in
                for lower in Swift.stride(from: offset, to: batchEnd, by: Int(stride)) {
                    let upper = min(bytes, lower + stride) - 1
                    group.addTask { try await Self.requestPart(url, offset: lower, end: upper, total: bytes, session: transport) }
                }
                var staged = [Int64: DownloadPart]()
                for try await part in group {
                    try Task.checkCancellation()
                    if part.wholeFile {
                        group.cancelAll()
                        guard try await Self.matches(file, at: part.url) else {
                            throw AudioFailure.message("下载校验失败，可继续下载")
                        }
                        // The existing checkpoint survives a corrupt response, a
                        // cancellation or a full-volume copy that fails partway.
                        _ = try fm.replaceItemAt(target, withItemAt: part.url, options: .usingNewMetadataOnly)
                        start = bytes
                        verifiedWhole = true
                        return
                    }
                    staged[part.offset] = part
                    // Only the contiguous prefix is ever checkpointed. A pause
                    // or a failed sibling leaves that prefix resumable on disk.
                    while let next = staged.removeValue(forKey: start) {
                        start += try Self.appendFile(next.url, to: out)
                    }
                }
            }
            acceptsRanges = true
        }
        if !verifiedWhole, try await !Self.matches(file, at: target) {
            try fm.removeItem(at: target)
            throw AudioFailure.message("下载校验失败，可重新下载")
        }
    }

    private static func matches(_ file: LocalModelManifest.File, at url: URL) async throws -> Bool {
        let worker = Task.detached(priority: .utility) { try digest(url) == file.sha256 }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func appendFile(_ url: URL, to out: FileHandle) throws -> Int64 {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var written: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count = try autoreleasepool { () throws -> Int in
                guard let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty else { return 0 }
                try out.write(contentsOf: chunk)
                return chunk.count
            }
            if count == 0 { break }
            written += Int64(count)
        }
        try out.synchronize()
        return written
    }

}
