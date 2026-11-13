import CloudKit
import Foundation

struct ReaderPage: Sendable {
    let items: [PrivateArchive]
    let removed: [UUID]
    let next: Data?
    let more: Bool
}
protocol ReaderSource: Sendable {
    func owner() async throws -> String
    func page(owner: String, after: Data?) async throws -> ReaderPage
    func audio(owner: String, item: PrivateArchive) async throws -> [URL]
}

// This adapter can only read. A phone cannot create a zone, write a record, or
// resurrect an asset. A change token is committed together with its metadata.
actor ReaderCloud: ReaderSource {
    private let container = CKContainer(identifier: ArchiveCloudRecord.containerID)
    func owner() async throws -> String {
        guard try await container.accountStatus() == .available else { throw ArchiveIssue.unavailable }
        return ArchiveCloudRecord.ownerKey(try await container.userRecordID().recordName)
    }
    func page(owner key: String, after: Data?) async throws -> ReaderPage {
        guard try await owner() == key else { throw ArchiveIssue.accountChanged }
        let db = container.privateCloudDatabase, zone = ArchiveCloudRecord.zoneID(ownerKey: key)
        let token = try after.map { data in
            guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) else { throw ArchiveIssue.cursorExpired }
            return token
        }
        do {
            let page = try await db.recordZoneChanges(inZoneWith: zone, since: token, desiredKeys: ArchiveCloudRecord.metadata, resultsLimit: 64)
            let items = try page.modificationResultsByID.values.compactMap { change -> PrivateArchive? in
                let record = try change.get().record
                return record.recordType == ArchiveCloudRecord.type ? try ArchiveCloudRecord.manifest(in: record) : nil
            }
            let removed = page.deletions.filter { $0.recordType == ArchiveCloudRecord.type }.compactMap { UUID(uuidString: $0.recordID.recordName) }
            let cursor = try NSKeyedArchiver.archivedData(withRootObject: page.changeToken, requiringSecureCoding: true)
            guard try await owner() == key else { throw ArchiveIssue.accountChanged }
            return ReaderPage(items: items, removed: removed, next: cursor, more: page.moreComing)
        } catch let error as CKError where [.changeTokenExpired,.zoneNotFound,.userDeletedZone].contains(error.code) {
            if after != nil { throw ArchiveIssue.cursorExpired }
            if error.code == .zoneNotFound || error.code == .userDeletedZone { return ReaderPage(items: [], removed: [], next: nil, more: false) }
            throw error
        }
    }
    func audio(owner key: String, item: PrivateArchive) async throws -> [URL] {
        guard try await owner() == key, !item.deleted, !item.audioDeleted, !item.chunks.isEmpty else { throw ArchiveIssue.stale }
        let id = CKRecord.ID(recordName: item.id.uuidString, zoneID: ArchiveCloudRecord.zoneID(ownerKey: key))
        let replies = try await container.privateCloudDatabase.records(for: [id], desiredKeys: ArchiveCloudRecord.metadata + [ArchiveCloudRecord.audio])
        guard let reply = replies[id] else { throw ArchiveIssue.invalid }
        let record = try reply.get(), now = try ArchiveCloudRecord.manifest(in: record)
        guard !now.deleted, !now.audioDeleted, now.chunks == item.chunks,
              let assets = record[ArchiveCloudRecord.audio] as? [CKAsset], assets.count == now.chunks.count,
              try await owner() == key else { throw ArchiveIssue.stale }
        return try assets.map { guard let url = $0.fileURL else { throw ArchiveIssue.invalid }; return url }
    }
}

struct ReaderSnapshot: Codable {
    var cursor: Data?
    var rows: [UUID: PrivateArchive] = [:]
}

actor ReaderDisk {
    let root: URL
    init(root: URL) { self.root = root }
    private func folder(_ key: String) throws -> URL {
        guard key.count == 64 && key.allSatisfy({ $0.isHexDigit }) else { throw ArchiveIssue.invalid }
        let dir = root.appendingPathComponent(key, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    func load(_ key: String) throws -> ReaderSnapshot {
        let file = try folder(key).appendingPathComponent("archive.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return .init() }
        return try JSONDecoder().decode(ReaderSnapshot.self, from: Data(contentsOf: file))
    }
    func save(_ value: ReaderSnapshot, key: String) throws {
        let dir = try folder(key)
        try JSONEncoder().encode(value).write(to: dir.appendingPathComponent("archive.json"), options: .atomic)
        let live = Set(value.rows.values.flatMap { $0.chunks.map(\.sha256) })
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
              where file.pathExtension == "wav" && !live.contains(file.deletingPathExtension().lastPathComponent) {
            try FileManager.default.removeItem(at: file)
        }
    }
    func parts(_ item: PrivateArchive, owner: String, source: any ReaderSource) async throws -> [URL] {
        // Identical content may be legitimately cached for a different record.
        // Check the current owner's manifest before every playback, including a
        // digest cache hit, then recheck after an asynchronous download.
        func requireCurrentAudio() throws {
            guard !item.deleted, !item.audioDeleted, !item.chunks.isEmpty,
                  let latest = try load(owner).rows[item.id],
                  !latest.deleted, !latest.audioDeleted, latest.chunks == item.chunks else { throw ArchiveIssue.stale }
        }
        try requireCurrentAudio()
        let dir = try folder(owner)
        let targets = item.chunks.map { dir.appendingPathComponent($0.sha256 + ".wav") }
        func valid(_ url: URL, _ chunk: PrivateArchive.Chunk) -> Bool {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
            return data.count == 44 + chunk.frames * 2 && ArchiveCloudRecord.digest(data) == chunk.sha256
        }
        if !zip(targets, item.chunks).allSatisfy({ valid($0, $1) }) {
            let paths = try await source.audio(owner: owner, item: item)
            try requireCurrentAudio()
            guard paths.count == targets.count else { throw ArchiveIssue.invalid }
            for (i, url) in paths.enumerated() {
                let bytes = try Data(contentsOf: url, options: .mappedIfSafe), chunk = item.chunks[i]
                guard bytes.count == 44 + chunk.frames * 2, ArchiveCloudRecord.digest(bytes) == chunk.sha256 else { throw ArchiveIssue.invalid }
                try bytes.write(to: targets[i], options: .atomic)
            }
        }
        // Evict older unrelated audio before playing. The current utterance
        // always remains complete even when it alone exceeds the cache budget.
        var size = 0
        let protected = Set(targets)
        let cached = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey,.contentModificationDateKey])
            .filter { $0.pathExtension == "wav" }.map { ($0, try $0.resourceValues(forKeys: [.fileSizeKey,.contentModificationDateKey])) }
            .sorted { ($0.1.contentModificationDate ?? .distantPast) > ($1.1.contentModificationDate ?? .distantPast) }
        for (url, attrs) in cached where protected.contains(url) { size += attrs.fileSize ?? 0; try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path) }
        for (url, attrs) in cached where !protected.contains(url) {
            if size + (attrs.fileSize ?? 0) > 128 * 1024 * 1024 { try FileManager.default.removeItem(at: url) }
            else { size += attrs.fileSize ?? 0 }
        }
        return targets
    }
}
