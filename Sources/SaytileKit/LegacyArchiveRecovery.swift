import Darwin
import Foundation

public enum LegacyArchiveRecovery {
    public struct Receipt: Codable, Sendable {
        public var examined = 0
        public var added = 0
        public var overlapping = 0
        public var keptLocalDeletions = 0
        public var keptLiveRecords = 0
        public var verifiedOriginals = 0
        public var verifiedBytes: Int64 = 0
    }

    /// All three paths must be explicit. Both original archives are quiescent
    /// read-only inputs. A partial result never becomes the requested output.
    public static func prepare(base: URL, legacy: URL, output: URL) async throws -> Receipt {
        let fm = FileManager.default
        for url in [base, legacy, output] { try StorePath.rejectSymbolicLink(url.standardizedFileURL) }
        let locations = [base, legacy, output].map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        for (i, location) in locations.enumerated() {
            for other in locations.dropFirst(i+1) {
                guard !location.pathComponents.starts(with: other.pathComponents),
                      !other.pathComponents.starts(with: location.pathComponents) else { throw StoreError.invalidPath }
            }
        }
        let destination = locations[2]
        guard !fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let working = destination.deletingLastPathComponent().appendingPathComponent(".saytile-recovery-" + UUID().uuidString)
        try fm.createDirectory(at: working, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: working) }
        let merged = working.appendingPathComponent("merged")
        let old = working.appendingPathComponent("legacy")
        try snapshot(locations[0], to: merged, includeAncillary: true)
        try snapshot(locations[1], to: old, includeAncillary: false)
        let first = try SaytileStore(directory: old)
        let target = try SaytileStore(directory: merged)
        let receipt: Receipt
        do {
            _ = try await AudioDiagnostics.recoverAudio(store: first)
            _ = try await AudioDiagnostics.recoverAudio(store: target)
            try await first.installArchiveTables()
            try await target.installArchiveTables()
            receipt = try await transfer(from: first, to: target)
            try await target.verifyArchiveSQLite()
            try await first.close()
            try await target.close()
        } catch {
            try? await first.close(); try? await target.close()
            throw error
        }
        guard renamex_np(merged.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return receipt
    }

    private static func snapshot(_ directory: URL, to copy: URL, includeAncillary: Bool) throws {
        let fm = FileManager.default
        let lock = directory.appendingPathComponent(".writer-lock")
        let descriptor = open(lock.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StoreError.database("未找到可验证的 Saytile 资料目录锁。") }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_SH | LOCK_NB) == 0 else { throw StoreError.database("这份资料正在使用。请先退出使用它的 Saytile。") }
        let database = directory.appendingPathComponent("Saytile.sqlite")
        guard try database.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw StoreError.invalidPath }
        try fm.createDirectory(at: copy, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let names = try fm.contentsOfDirectory(atPath: directory.path)
        for name in names where ![".writer-lock", "Saytile.sqlite-shm"].contains(name) {
            if includeAncillary || ["Saytile.sqlite", "Saytile.sqlite-wal", "Audio"].contains(name) {
                try copyTree(directory.appendingPathComponent(name), to: copy.appendingPathComponent(name))
            }
        }
    }

    private static func copyTree(_ source: URL, to destination: URL) throws {
        try Task.checkCancellation()
        try StorePath.rejectSymbolicLink(source)
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        let fm = FileManager.default
        if values.isDirectory == true {
            try fm.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                try copyTree(item, to: destination.appendingPathComponent(item.lastPathComponent))
            }
        } else {
            guard values.isRegularFile == true else { throw StoreError.invalidPath }
            try fm.copyItem(at: source, to: destination)
        }
    }

    private static func transfer(from source: SaytileStore, to target: SaytileStore) async throws -> Receipt {
        var receipt = Receipt()
        var position: Int64 = 0
        while true {
            let batch = try await source.archiveIDs(after: position)
            if batch.isEmpty { break }
            for (next, id) in batch {
                try Task.checkCancellation()
                position = next
                guard let item = try await source.exportArchive(id) else { throw ArchiveIssue.invalid }
                let existing = try await target.exportArchive(id)
                receipt.examined += 1
                if let existing {
                    receipt.overlapping += 1
                    if existing.deleted { receipt.keptLocalDeletions += 1; continue }
                    if item.deleted { receipt.keptLiveRecords += 1; continue }
                } else { receipt.added += 1 }
                try await target.applyArchiveText(item, localImport: true)
                if !item.chunks.isEmpty && existing?.audioDeleted != true {
                    let files = try await source.archiveAssetURLs(item)
                    try await target.installArchiveAssets(item, files: files, localImport: true)
                    guard try await target.exportArchive(id)?.chunks == item.chunks else { throw ArchiveIssue.invalid }
                    receipt.verifiedOriginals += item.chunks.count
                    receipt.verifiedBytes += item.chunks.reduce(0) { $0 + 44 + $1.frames * 2 }
                }
                guard let saved = try await target.exportArchive(id),
                      item.versions.allSatisfy(saved.versions.contains),
                      item.draft == nil || item.draft == saved.draft || saved.versions.contains(item.draft!) else { throw ArchiveIssue.invalid }
            }
        }
        return receipt
    }
}

extension SaytileStore {
    fileprivate func archiveIDs(after position: Int64) throws -> [(Int64,UUID)] {
        try db.rows("SELECT position,recording_id FROM transcript_timeline WHERE recording_id IS NOT NULL AND position>? ORDER BY position LIMIT 64", [.int(position)]).map {
            guard let next = $0["position"].flatMap(Int64.init), let id = $0["recording_id"].flatMap(UUID.init(uuidString:)) else { throw ArchiveIssue.invalid }
            return (next,id)
        }
    }
    fileprivate func verifyArchiveSQLite() throws {
        guard try db.rows("PRAGMA integrity_check").first?["integrity_check"] == "ok",
              try db.rows("PRAGMA foreign_key_check").isEmpty else { throw ArchiveIssue.invalid }
    }
}
