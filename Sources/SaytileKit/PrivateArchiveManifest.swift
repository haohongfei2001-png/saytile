import Foundation

// The wire format contains archive data only. Recognition credentials, delivery
// bindings, model caches, device IDs and temporary recognition candidates stay local.
struct PrivateArchive: Codable, Equatable, Sendable {
    struct Version: Codable, Equatable, Sendable {
        let id: UUID
        let text: String
        let origin: RevisionOrigin
        let created: Double
        let attempt: UUID?
        let base: UUID?
    }
    struct Chunk: Codable, Equatable, Sendable {
        let id: UUID
        let frames: Int64
        let ordinal: Int
        let sha256: String
    }
    struct Group: Codable, Equatable, Sendable {
        let start: Double
        let day: String
        let offset: Int
    }
    let format: Int
    let id: UUID
    let started: Double
    let ended: Double?
    let day: String
    let offset: Int
    let group: Group
    let sampleRate: Double
    var sequence: Int64? = nil
    var head: UUID?
    var pinned: Bool
    var deleted: Bool
    var audioDeleted: Bool
    var draft: Version? = nil
    var versions: [Version]
    var chunks: [Chunk]

    static func checked(_ condition: Bool) throws {
        guard condition else { throw ArchiveIssue.invalid }
    }
    func validate() throws {
        try Self.checked(format == 1 && started.isFinite && sampleRate.isFinite && sampleRate > 0 &&
            (ended?.isFinite ?? true) && group.start.isFinite && !day.isEmpty && !group.day.isEmpty)
        try Self.checked(Set(versions.map(\.id)).count == versions.count &&
            Set(chunks.map(\.id)).count == chunks.count &&
            (head == nil || versions.contains { $0.id == head }) &&
            (!audioDeleted || chunks.isEmpty) && (!deleted || (head == nil && draft == nil && versions.isEmpty && audioDeleted)))
        if let draft { try Self.checked(draft.origin == .userEdit && draft.created.isFinite) }
        for v in versions { try Self.checked(v.created.isFinite) }
        for (n, c) in chunks.enumerated() {
            try Self.checked(c.ordinal == n && c.frames >= 0 && c.frames <= (Int64(UInt32.max) - 36) / 2 &&
                c.sha256.utf8.count == 64 && c.sha256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
        }
    }

    func merged(with remote: Self, baseline: Self?) throws -> Self {
        try validate()
        try remote.validate()
        try Self.checked(id == remote.id && started == remote.started && sampleRate == remote.sampleRate)
        var result = self
        if deleted || remote.deleted {
            result.head = nil; result.deleted = true; result.audioDeleted = true; result.pinned = false
            result.draft = nil; result.versions = []; result.chunks = []
            return result
        }
        result.audioDeleted = audioDeleted || remote.audioDeleted
        if result.audioDeleted { result.chunks = [] }
        else {
            if !chunks.isEmpty && !remote.chunks.isEmpty { try Self.checked(chunks == remote.chunks) }
            result.chunks = chunks.isEmpty ? remote.chunks : chunks
        }
        var byID = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0) })
        for version in remote.versions {
            if let existing = byID[version.id] { try Self.checked(existing == version) }
            byID[version.id] = version
        }
        if draft != remote.draft {
            if draft == baseline?.draft { result.draft = remote.draft }
            else if remote.draft != baseline?.draft {
                let candidates = [draft, remote.draft].compactMap { $0 }.sorted {
                    ($0.created,$0.id.uuidString) < ($1.created,$1.id.uuidString)
                }
                result.draft = candidates.last
                for v in candidates.dropLast() {
                    if let old = byID[v.id] { try Self.checked(old == v) }
                    byID[v.id] = v
                }
            }
        }
        result.versions = byID.values.sorted { ($0.created, $0.id.uuidString) < ($1.created, $1.id.uuidString) }
        // A manual selection on just one device wins. When both heads diverge,
        // preserve both versions and prefer an explicit edit to recognition.
        if head == baseline?.head && remote.head != baseline?.head { result.head = remote.head }
        else if head != remote.head && remote.head != baseline?.head {
            let options = [head, remote.head].compactMap { $0 }.compactMap { byID[$0] }
            result.head = options.max {
                ($0.origin == .userEdit ? 1 : 0, $0.created, $0.id.uuidString) <
                ($1.origin == .userEdit ? 1 : 0, $1.created, $1.id.uuidString)
            }?.id
        }
        if let localHead = head.flatMap({ byID[$0] }), localHead.origin == .userEdit,
           result.head.flatMap({ byID[$0] })?.origin != .userEdit { result.head = localHead.id }
        if pinned == baseline?.pinned { result.pinned = remote.pinned }
        else if baseline == nil { result.pinned = pinned || remote.pinned }
        return result
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

enum ArchiveIssue: Error, LocalizedError {
    case invalid, unavailable, accountChanged, stale, cursorExpired
    var errorDescription: String? {
        switch self {
        case .invalid: "iCloud 档案校验失败，已保留本机资料。"
        case .unavailable: "等待 iCloud 可用"
        case .accountChanged: "Apple 账户已更改，档案同步已暂停。"
        case .stale: "档案已更新，等待同步最新版本。"
        case .cursorExpired: "正在重新核对 iCloud 档案"
        }
    }
}

