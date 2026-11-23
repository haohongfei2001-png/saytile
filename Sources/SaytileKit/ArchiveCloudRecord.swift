import CloudKit
import CryptoKit
import Foundation

// The manifest and audio attachments share a change tag and are saved atomically.
// Fetching manifests for the archive list never downloads the associated WAVs.
enum ArchiveCloudRecord {
    static let containerID = "iCloud.app.saytile.archive"
    static func ownerKey(_ raw: String) -> String {
        digest(Data(raw.utf8))
    }

    static func zoneID(ownerKey: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "SaytileArchiveV1-" + ownerKey.prefix(32), ownerName: CKCurrentUserDefaultName)
    }

    static let type = "SaytileRecordingV1"
    static let metadata = ["manifest", "manifestFile", "manifestSHA256", "partCount"]
    static let audio = "audioParts"

    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func manifest(in record: CKRecord) throws -> PrivateArchive {
        guard record.recordType == type else { throw ArchiveIssue.invalid }
        let inline = record["manifest"] as? Data
        let file = record["manifestFile"] as? CKAsset
        let bytes: Data
        switch (inline, file) {
        case (let data?, nil): bytes = data
        case (nil, let asset?):
            guard let url = asset.fileURL else { throw ArchiveIssue.invalid }
            bytes = try Data(contentsOf: url)
        default: throw ArchiveIssue.invalid
        }
        let result = try JSONDecoder().decode(PrivateArchive.self, from: bytes)
        try result.validate()
        guard record.recordID.recordName == result.id.uuidString,
              record["manifestSHA256"] as? String == digest(bytes),
              (record["partCount"] as? NSNumber)?.intValue == result.chunks.count
        else { throw ArchiveIssue.invalid }
        return result
    }

    static func setManifest(_ bytes: Data, parts: Int, on record: CKRecord, staging: URL) throws {
        if bytes.count <= 256 * 1024 {
            record["manifest"] = bytes
            record["manifestFile"] = nil
        } else {
            let url = staging.appendingPathComponent("manifest.json")
            try bytes.write(to: url, options: .withoutOverwriting)
            record["manifest"] = nil
            record["manifestFile"] = CKAsset(fileURL: url)
        }
        record["manifestSHA256"] = digest(bytes)
        record["partCount"] = parts
    }
}
