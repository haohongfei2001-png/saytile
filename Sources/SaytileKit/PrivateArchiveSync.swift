import Foundation
import CloudKit

protocol PrivateArchiveTransport: Sendable {
    func account() async throws -> String
    func changes(after cursor: String?) async throws -> (items: [PrivateArchive], cursor: String, more: Bool)
    func upload(_ local: PrivateArchive, baseline: PrivateArchive?, files: [URL]) async throws -> PrivateArchive
    func download(_ manifest: PrivateArchive) async throws -> [URL]
}

public struct PrivateArchiveSync: Sendable {
    let store: SaytileStore
    let remote: any PrivateArchiveTransport

    public static func configured(for store: SaytileStore) -> Self? {
        ApplePrivateArchive.transportIfEntitled().map { Self(store: store, remote: $0) }
    }

    // Awaiting one pass serially also prevents concurrent retries. All queues and
    // cursors survive process termination; only transient CloudKit files do not.
    func synchronize(report: @Sendable (String) async -> Void) async throws {
        let owner = try await remote.account()
        try await store.enablePrivateArchive(owner: owner)
        var cursor = try await store.archiveState("cursor").flatMap { $0.isEmpty ? nil : $0 }
        repeat {
            try Task.checkCancellation()
            let page: (items: [PrivateArchive], cursor: String, more: Bool)
            do { page = try await remote.changes(after: cursor) }
            catch ArchiveIssue.cursorExpired where cursor != nil {
                try await store.setArchiveState("cursor", "")
                cursor = nil
                continue
            }
            if !page.items.isEmpty { await report("正在获取档案文字") }
            try await store.stageArchivePage(page.items, cursor: page.cursor)
            cursor = page.cursor
            if !page.more { break }
        } while true

        try await store.prepareArchiveRestoreOrder()
        var recovered = 0
        var lastFailure: Error?
        var itemCursor: Int64 = 0
        while let (position,manifest) = try await store.nextArchiveRestore(after: itemCursor) {
            itemCursor = position
            try Task.checkCancellation()
            do { try await store.applyArchiveText(manifest) }
            catch { lastFailure = error; continue }
            recovered += 1
            if recovered == 1 || recovered.isMultiple(of: 20) { await report("已恢复 \(recovered) 条文字档案") }
        }
        var audio = 0
        itemCursor = 0
        while let (position,manifest) = try await store.nextArchiveAssets(after: itemCursor) {
            itemCursor = position
            try Task.checkCancellation()
            await report("正在恢复原音 · 已完成 \(audio) 条")
            do {
                let urls = try await remote.download(manifest)
                try await store.installArchiveAssets(manifest, files: urls)
            } catch {
                try Self.deferIndividualFailure(error)
                lastFailure = error; continue
            }
            audio += 1
        }
        var lastID = ""
        while true {
            let batch = try await store.archivePending(after: lastID)
            if batch.isEmpty { break }
            for (id, generation) in batch {
                lastID = id.uuidString
                do {
                    try Task.checkCancellation()
                    guard let occurrence = try await store.exportArchive(id) else { throw ArchiveIssue.invalid }
                    let baseline = try await store.archiveBaseline(id)
                    if occurrence == baseline {
                        try await store.acknowledgeArchive(occurrence, generation: generation)
                        continue
                    }
                    await report("正在同步")
                    let files = try await store.archiveAssetURLs(occurrence)
                    // Bind a confirmed server response to this generation only. A
                    // pin/edit/erasure made in flight always survives the acknowledgement.
                    let saved = try await remote.upload(occurrence, baseline: baseline, files: files)
                    if saved == occurrence {
                        try await store.acknowledgeArchive(saved,generation: generation)
                    } else {
                        try await store.applyArchiveText(saved)
                        // Remote audio can win a metadata-only merge. Fetch before
                        // calling the archive complete, including on a new machine.
                        if let needed = try await store.nextArchiveAssets(for: id) {
                            try await store.installArchiveAssets(needed, files: try await remote.download(needed))
                        }
                    }
                } catch {
                    try Self.deferIndividualFailure(error)
                    lastFailure = error
                }
            }
        }
        if let lastFailure { throw lastFailure }
        await report(try await store.archiveCompletionSummary())
    }

    private static func deferIndividualFailure(_ error: Error) throws {
        if error is ArchiveIssue || error is StoreError { return }
        throw error
    }
    public func run(report: @escaping @Sendable (String) async -> Void) async {
        var failures = 0
        while !Task.isCancelled {
            var delay: Double = 45
            do {
                try await synchronize(report: report)
                failures = 0
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                failures = min(failures + 1, 6)
                delay = max(pow(2,Double(failures))*5, (error as? CKError)?.retryAfterSeconds ?? 0)
                switch (error as? CKError)?.code {
                case .networkUnavailable,.networkFailure,.notAuthenticated,.accountTemporarilyUnavailable:
                    await report("等待网络或 iCloud")
                case .quotaExceeded: await report("iCloud 空间不足")
                default: await report(error.localizedDescription)
                }
            }
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        }
    }
}

extension SaytileStore {
    func archiveCompletionSummary() throws -> String {
        if try !archivePending().isEmpty { return "正在同步" }
        if try !db.rows("SELECT 1 FROM recordings WHERE is_recording=0 AND deleted=0 AND audio_state='missing' LIMIT 1").isEmpty {
            return "文字已备份 · 部分原音缺失"
        }
        if try db.rows("SELECT 1 FROM icloud_baseline LIMIT 1").isEmpty { return "暂无已完成的档案" }
        return "已备份"
    }
}
