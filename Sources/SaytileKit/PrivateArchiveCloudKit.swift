import CloudKit
import Foundation
import Security

enum ApplePrivateArchive {
    static let candidateBundleID = "app.saytile.mac.icloud-candidate"

    static func transportIfEntitled() -> (any PrivateArchiveTransport)? {
        // CKContainer can terminate an unsigned process before returning a CKError.
        // Only the explicitly provisioned candidate can reach the test container.
        guard Bundle.main.bundleIdentifier == candidateBundleID,
              let task = SecTaskCreateFromSelf(nil),
              let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String],
              services.contains("CloudKit"),
              let ids = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String],
              ids.contains(ArchiveCloudRecord.containerID),
              let environment = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-environment" as CFString, nil) as? String,
              environment == "Development" else { return nil }
        return CloudKitArchiveTransport(container: CKContainer(identifier: ArchiveCloudRecord.containerID))
    }
}

private enum ArchiveCloudError: LocalizedError {
    case zoneRemoved
    case recordRemoved
    var errorDescription: String? {
        switch self {
        case .zoneRemoved: "iCloud 备份区域已移除，已保留本机档案。"
        case .recordRemoved: "iCloud 备份记录已被移除，已保留本机档案。"
        }
    }
}

private actor CloudKitArchiveTransport: PrivateArchiveTransport {
    private let container: CKContainer
    private let database: CKDatabase
    private var owner: String?

    init(container: CKContainer) {
        self.container = container
        database = container.privateCloudDatabase
    }

    private func accountKey() async throws -> String {
        guard try await container.accountStatus() == .available else { throw ArchiveIssue.unavailable }
        return ArchiveCloudRecord.ownerKey(try await container.userRecordID().recordName)
    }

    func account() async throws -> String {
        let key = try await accountKey()
        owner = key
        return key
    }

    private func currentZone() async throws -> CKRecordZone.ID {
        guard let owner, try await accountKey() == owner else { throw ArchiveIssue.accountChanged }
        // A request in flight during an Apple account switch cannot address a
        // preexisting archive in the new account under the old account's zone.
        return ArchiveCloudRecord.zoneID(ownerKey: owner)
    }

    func changes(after cursor: String?) async throws -> (items: [PrivateArchive], cursor: String, more: Bool) {
        let zone = try await currentZone()
        var token: CKServerChangeToken?
        if let cursor {
            guard let bytes = Data(base64Encoded: cursor),
                  let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: bytes)
            else { throw ArchiveIssue.cursorExpired }
            token = saved
        } else {
            do { _ = try await database.recordZone(for: zone) }
            catch let error as CKError where error.code == .zoneNotFound {
                guard try await currentZone() == zone else { throw ArchiveIssue.accountChanged }
                _ = try await database.save(CKRecordZone(zoneID: zone))
            }
        }
        do {
            let page = try await database.recordZoneChanges(inZoneWith: zone, since: token,
                                                            desiredKeys: ArchiveCloudRecord.metadata, resultsLimit: 32)
            // The archive format uses durable tombstones, never record deletion.
            if page.deletions.contains(where: { $0.recordType == ArchiveCloudRecord.type }) {
                throw ArchiveCloudError.recordRemoved
            }
            var items: [PrivateArchive] = []
            for (_, change) in page.modificationResultsByID {
                let record = try change.get().record
                if record.recordType == ArchiveCloudRecord.type {
                    items.append(try ArchiveCloudRecord.manifest(in: record))
                }
            }
            let next = try NSKeyedArchiver.archivedData(withRootObject: page.changeToken, requiringSecureCoding: true)
            return (items, next.base64EncodedString(), page.moreComing)
        } catch let error as CKError {
            switch error.code {
            case .changeTokenExpired: throw ArchiveIssue.cursorExpired
            case .zoneNotFound, .userDeletedZone: throw ArchiveCloudError.zoneRemoved
            default: throw error
            }
        }
    }

    private func fetch(_ id: CKRecord.ID, includeAudio: Bool = false) async throws -> CKRecord {
        let keys = ArchiveCloudRecord.metadata + (includeAudio ? [ArchiveCloudRecord.audio] : [])
        let responses = try await database.records(for: [id], desiredKeys: keys)
        guard let response = responses[id] else { throw ArchiveIssue.invalid }
        return try response.get()
    }

    func upload(_ local: PrivateArchive, baseline: PrivateArchive?, files: [URL]) async throws -> PrivateArchive {
        try local.validate()
        let zone = try await currentZone()
        let id = CKRecord.ID(recordName: local.id.uuidString, zoneID: zone)
        let fetched: CKRecord?
        do {
            fetched = try await fetch(id)
        } catch let error as CKError where error.code == .unknownItem {
            // Previously confirmed content disappearing remotely is different
            // from this device uploading a genuinely new recording.
            guard baseline == nil else { throw ArchiveCloudError.recordRemoved }
            fetched = nil
        }
        let record = fetched ?? CKRecord(recordType: ArchiveCloudRecord.type, recordID: id)
        let existing = try fetched.map { try ArchiveCloudRecord.manifest(in: $0) }
        let merged = try existing.map { try local.merged(with: $0, baseline: baseline) } ?? local
        if merged == existing { return merged }

        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-cloud-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let bytes = try merged.encoded()
        try ArchiveCloudRecord.setManifest(bytes, parts: merged.chunks.count, on: record, staging: staging)
        if merged.audioDeleted {
            record[ArchiveCloudRecord.audio] = nil
        } else if !merged.chunks.isEmpty && merged.chunks != existing?.chunks {
            guard merged.chunks == local.chunks, files.count == merged.chunks.count else { throw ArchiveIssue.invalid }
            // Freeze and verify the exact bytes CloudKit will read; deletion or
            // a local recovery race cannot silently upload different audio.
            let assets = try zip(merged.chunks, files).map { chunk, source -> CKAsset in
                let file = staging.appendingPathComponent(chunk.id.uuidString + ".wav")
                try FileManager.default.copyItem(at: source, to: file)
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                guard ArchiveCloudRecord.digest(data) == chunk.sha256 else { throw ArchiveIssue.invalid }
                return CKAsset(fileURL: file)
            }
            record[ArchiveCloudRecord.audio] = assets
        }
        guard try await currentZone() == zone else { throw ArchiveIssue.accountChanged }
        do {
            let saved = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
            guard let response = saved.saveResults[id] else { throw ArchiveIssue.invalid }
            let confirmed = try response.get()
            guard confirmed.recordChangeTag != nil, confirmed.recordID == id,
                  confirmed["manifestSHA256"] as? String == ArchiveCloudRecord.digest(bytes),
                  (confirmed["partCount"] as? NSNumber)?.intValue == merged.chunks.count else { throw ArchiveIssue.invalid }
            return merged
        } catch let error as CKError where error.code == .serverRecordChanged {
            throw ArchiveIssue.stale
        }
    }

    func download(_ manifest: PrivateArchive) async throws -> [URL] {
        try manifest.validate()
        guard !manifest.chunks.isEmpty else { return [] }
        let id = CKRecord.ID(recordName: manifest.id.uuidString, zoneID: try await currentZone())
        let record = try await fetch(id, includeAudio: true)
        let current = try ArchiveCloudRecord.manifest(in: record)
        // Unrelated text edits do not invalidate an immutable audio download.
        guard !current.audioDeleted, current.chunks == manifest.chunks else { throw ArchiveIssue.stale }
        guard let parts = record[ArchiveCloudRecord.audio] as? [CKAsset],
              parts.count == manifest.chunks.count else { throw ArchiveIssue.invalid }
        return try parts.map {
            guard let url = $0.fileURL else { throw ArchiveIssue.invalid }
            return url
        }
    }
}
