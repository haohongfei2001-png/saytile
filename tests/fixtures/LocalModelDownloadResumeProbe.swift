import CryptoKit
import Darwin
import Foundation
import SaytileKit

// A bounded, real HTTPS acceptance probe for the shipped library. It never loads
// an ASR model or uses a production cache. All query strings (including CDN
// signatures) are omitted from the receipt.
final class ResumeNetworkObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Transaction: Codable, Sendable {
        let host: String
        let path: String
        let range: String?
        let status: Int?
        let contentRange: String?
        let receivedBodyBytes: Int64
    }
    struct Observation: Codable, Sendable {
        let task: Int
        let transactions: [Transaction]
    }
    private let lock = NSLock()
    private var observations: [Observation] = []
    private var cancelledOversizedResponses = 0
    private var createdTasks = 0
    private let maximumBodyBytes: Int64
    init(maximumBodyBytes: Int64) { self.maximumBodyBytes = maximumBodyBytes }
    func snapshot() -> ([Observation], Int) {
        lock.lock(); defer { lock.unlock() }
        return (observations, cancelledOversizedResponses)
    }
    func taskCount() -> Int { lock.lock(); defer { lock.unlock() }; return createdTasks }
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.lock(); createdTasks += 1; lock.unlock()
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumBodyBytes || totalBytesExpectedToWrite > maximumBodyBytes {
            lock.lock(); cancelledOversizedResponses += 1; lock.unlock()
            downloadTask.cancel()
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let items = metrics.transactionMetrics.map { item in
            let response = item.response as? HTTPURLResponse
            return Transaction(host: item.request.url?.host ?? "", path: item.request.url?.path ?? "",
                range: item.request.value(forHTTPHeaderField: "Range"), status: response?.statusCode,
                contentRange: response?.value(forHTTPHeaderField: "Content-Range"),
                receivedBodyBytes: item.countOfResponseBodyBytesReceived)
        }
        lock.lock(); observations.append(Observation(task: task.taskIdentifier, transactions: items)); lock.unlock()
    }
}

@main
struct LocalModelDownloadResumeProbe {
    struct FileDigest: Codable, Equatable, Sendable {
        let path: String
        let bytes: Int64
        let sha256: String
    }
    struct Receipt: Codable {
        var status = "FAIL"
        var sourceRevision: String
        var startedAt = ISO8601DateFormatter().string(from: Date())
        var finishedAt: String?
        var modelRevision: String?
        var sourceRepo: String?
        var cloneMethod = "APFS clonefile; independent copy-on-write files"
        var missingBytes: Int64 = 65_536
        var sourceVerified = false
        var sourceUnchanged = false
        var partialBefore: [FileDigest] = []
        var partialAfterFailure: [FileDigest] = []
        var partialPreservedOnFailure: Bool?
        var installedFiles: [FileDigest] = []
        var freshLibraryValidation = false
        var firstDownloadSeconds: Double?
        var repeatDownloadNoNetwork: Bool?
        var network: [ResumeNetworkObserver.Observation] = []
        var oversizedResponsesCancelled = 0
        var createdNetworkTasks = 0
        var libraryError: String?
        var transientNetworkFailure: Bool?
        var error: String?
    }
    struct Stop: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func digests(_ files: [LocalModelManifest.File], at directory: URL) async throws -> [FileDigest] {
        try await Task.detached(priority: .utility) {
            try files.map { item in
                let url = directory.appendingPathComponent(item.path)
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var sha = SHA256(), bytes: Int64 = 0
                while true {
                    let count = try autoreleasepool {
                        guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { return 0 }
                        sha.update(data: data)
                        return data.count
                    }
                    if count == 0 { break }
                    bytes += Int64(count)
                }
                return FileDigest(path: item.path, bytes: bytes, sha256: sha.finalize().map { String(format: "%02x", $0) }.joined())
            }
        }.value
    }
    static func matches(_ values: [FileDigest], manifest: LocalModelManifest) -> Bool {
        values.count == manifest.files.count && zip(values, manifest.files).allSatisfy {
            $0.path == $1.path && $0.bytes == $1.bytes && $0.sha256 == $1.sha256
        }
    }
    static func main() async {
        guard CommandLine.arguments.count == 5 else { print("usage: probe SOURCE_WEIGHTS EMPTY_ROOT RECEIPT SOURCE_SHA"); exit(64) }
        let source = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.resolvingSymlinksInPath()
        let root = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL.resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        var receipt = Receipt(sourceRevision: CommandLine.arguments[4])
        let observer = ResumeNetworkObserver(maximumBodyBytes: receipt.missingBytes)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 45
        // No proxy overrides, URLProtocol mocks, alternate hosts or altered manifest.
        let session = URLSession(configuration: config, delegate: observer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            // Foundation can canonicalize /private/tmp to /tmp. Apply the same
            // canonicalization to the allowlist before testing its boundary.
            let research = URL(fileURLWithPath: "/private/tmp/saytile-beta-021-20261123/.build/local-asr/weights")
                .standardizedFileURL.resolvingSymlinksInPath().path + "/"
            let temporary = URL(fileURLWithPath: "/private/tmp").standardizedFileURL.resolvingSymlinksInPath().path
            let rootParent = root.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
            guard source.path.hasPrefix(research), rootParent == temporary,
                  root.lastPathComponent.hasPrefix("saytile-model-resume-"),
                  !FileManager.default.fileExists(atPath: root.path) else {
                throw Stop(message: "Expected the authorized research weights and a new isolated /private/tmp root")
            }
            let manifest = try LocalModelManifest.load(.qwen)
            receipt.modelRevision = manifest.revision; receipt.sourceRepo = manifest.repo
            guard source.lastPathComponent == manifest.revision,
                  let weights = manifest.files.first(where: { $0.path == "model.safetensors" }), weights.bytes > receipt.missingBytes else {
                throw Stop(message: "Pinned model/revision mismatch")
            }
            let original = try await digests(manifest.files, at: source)
            receipt.sourceVerified = matches(original, manifest: manifest)
            guard receipt.sourceVerified else { throw Stop(message: "Source fixture does not match the shipped six-file manifest") }
            let parent = root.appendingPathComponent(manifest.id.rawValue)
            let stage = parent.appendingPathComponent(manifest.revision + ".partial")
            let installed = parent.appendingPathComponent(manifest.revision)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            for item in manifest.files {
                let from = source.appendingPathComponent(item.path), to = stage.appendingPathComponent(item.path)
                guard clonefile(from.path, to.path, 0) == 0 else { throw Stop(message: "APFS clone failed: \(errno)") }
            }
            let tail = try FileHandle(forWritingTo: stage.appendingPathComponent(weights.path))
            try tail.truncate(atOffset: UInt64(weights.bytes - receipt.missingBytes)); try tail.synchronize(); try tail.close()
            receipt.partialBefore = try await digests(manifest.files, at: stage)
            let library = LocalModelLibrary(root: root, session: session)
            let before = await library.status(.qwen)
            guard !before.installed, !before.downloading, before.bytes == manifest.size - receipt.missingBytes,
                  before.total == manifest.size else { throw Stop(message: "Partial checkpoint became usable or has the wrong offset") }
            print("RESUME_BEGIN missing_bytes=\(receipt.missingBytes) manifest_revision=\(manifest.revision)"); fflush(nil)
            let start = ProcessInfo.processInfo.systemUptime
            let task = await library.download(.qwen)
            let timeout = Task {
                do { try await Task.sleep(for: .seconds(58)); await library.pause(.qwen) } catch {}
            }
            await task?.value
            timeout.cancel()
            receipt.firstDownloadSeconds = ProcessInfo.processInfo.systemUptime - start
            let result = await library.status(.qwen)
            receipt.libraryError = result.error
            receipt.transientNetworkFailure = await library.needsNetworkToResume(.qwen)
            if result.installed {
                let reopened = LocalModelLibrary(root: root, session: session)
                receipt.freshLibraryValidation = await reopened.status(.qwen).installed
                receipt.installedFiles = try await digests(manifest.files, at: installed)
                guard receipt.freshLibraryValidation, matches(receipt.installedFiles, manifest: manifest),
                      !FileManager.default.fileExists(atPath: stage.path) else { throw Stop(message: "Installed file or fresh-library validation mismatch") }
                try await Task.sleep(for: .milliseconds(100))
                let beforeRepeat = observer.taskCount()
                guard beforeRepeat > 0, !observer.snapshot().0.isEmpty else { throw Stop(message: "URLSession metrics unavailable; cannot prove actual transfer or no-request repeat") }
                let repeated = await reopened.download(.qwen)
                await repeated?.value
                try await Task.sleep(for: .milliseconds(100))
                receipt.repeatDownloadNoNetwork = observer.taskCount() == beforeRepeat
                guard receipt.repeatDownloadNoNetwork == true else { throw Stop(message: "Repeat download unexpectedly requested the network") }
                receipt.status = "PASS"
            } else {
                receipt.partialAfterFailure = try await digests(manifest.files, at: stage)
                receipt.partialPreservedOnFailure = receipt.partialBefore == receipt.partialAfterFailure
                receipt.status = receipt.partialPreservedOnFailure == true ? "BLOCKED_NETWORK" : "FAIL"
            }
            receipt.sourceUnchanged = original == (try await digests(manifest.files, at: source))
            guard receipt.sourceUnchanged else { throw Stop(message: "Read-only research source changed") }
        } catch { receipt.error = error.localizedDescription; receipt.status = "FAIL" }
        receipt.finishedAt = ISO8601DateFormatter().string(from: Date())
        (receipt.network, receipt.oversizedResponsesCancelled) = observer.snapshot()
        receipt.createdNetworkTasks = observer.taskCount()
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(receipt).write(to: output, options: .atomic)
        } catch { print("RECEIPT_WRITE_FAILED"); exit(2) }
        print("RESUME_RESULT \(receipt.status) tasks=\(receipt.network.count) source_unchanged=\(receipt.sourceUnchanged)")
        exit(receipt.status == "PASS" ? 0 : receipt.status == "BLOCKED_NETWORK" ? 3 : 1)
    }
}
