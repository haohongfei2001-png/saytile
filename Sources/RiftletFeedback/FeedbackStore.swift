import Foundation
import CSQLite
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Owns the SQLite connection and process lock; referenced only by FeedbackStore.
/// ARC releases these resources after the actor is no longer reachable, without
/// an isolated actor destructor that triggers cross-module WMO compiler cycles.
private final class FeedbackStoreResources {
    var db: OpaquePointer?
    var descriptor: Int32
    init(db: OpaquePointer?, descriptor: Int32) { self.db = db; self.descriptor = descriptor }
    deinit { if let db { sqlite3_close(db) }; if descriptor >= 0 { close(descriptor) } }
}

/// Independent sidecar. It never opens queue.sqlite or a media directory.
public actor FeedbackStore {
    private let resources: FeedbackStoreResources
    private var db: OpaquePointer? {
        get { resources.db }
        set { resources.db = newValue }
    }
    private var descriptor: Int32 {
        get { resources.descriptor }
        set { resources.descriptor = newValue }
    }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public nonisolated let wasUnclean: Bool

    public init(directory: URL) throws {
        var handle: OpaquePointer?
        var lockFD: Int32 = -1
        do {
            // lstat also rejects dangling links and named pipes without opening
            // them. fileExists() alone follows links and misses dangling ones.
            func checkExisting(_ path: String, directory: Bool = false) throws {
                var info = stat()
                if lstat(path, &info) != 0 {
                    guard errno == ENOENT else { throw FeedbackFailure.storageUnavailable }
                    return
                }
                let wanted = directory ? mode_t(S_IFDIR) : mode_t(S_IFREG)
                guard info.st_mode & mode_t(S_IFMT) == wanted else { throw FeedbackFailure.storageUnavailable }
            }
            try checkExisting(directory.path, directory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            guard chmod(directory.path, 0o700) == 0 else { throw FeedbackFailure.storageUnavailable }
            let lockPath = directory.appendingPathComponent("feedback.lock").path
            try checkExisting(lockPath)
            lockFD = open(lockPath, O_CREAT | O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw FeedbackFailure.storageUnavailable }
            var lockInfo = stat()
            guard fstat(lockFD, &lockInfo) == 0, lockInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  fchmod(lockFD, 0o600) == 0 else { throw FeedbackFailure.storageUnavailable }
            let url = directory.appendingPathComponent("feedback.sqlite")
            for suffix in ["", "-journal", "-wal", "-shm"] { try checkExisting(url.path + suffix) }
            let fd = open(url.path, O_CREAT | O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw FeedbackFailure.storageUnavailable }
            var info = stat()
            let regular = fstat(fd, &info) == 0 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
            let privateFile = fchmod(fd, 0o600) == 0
            close(fd)
            guard regular, privateFile,
                  sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                throw FeedbackFailure.storageUnavailable
            }
            sqlite3_busy_timeout(handle, 200)
            func exec(_ sql: String) throws {
                guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }
            }
            var version: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &version, nil) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }
            defer { sqlite3_finalize(version) }
            guard sqlite3_step(version) == SQLITE_ROW else { throw FeedbackFailure.storageUnavailable }
            let v = sqlite3_column_int(version, 0)
            guard v == 0 || v == 1 else { throw FeedbackFailure.storageUnavailable }
            // Clear removed text from the live sidecar's freed cells/pages.
            // This does not claim erasure from OS snapshots or external backups.
            try exec("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA trusted_schema=OFF; PRAGMA secure_delete=ON;")
            try exec("BEGIN IMMEDIATE")
            do {
                try exec("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL); CREATE TABLE IF NOT EXISTS draft(id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL,payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY,payload BLOB NOT NULL,state TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,next_attempt REAL NOT NULL,created REAL NOT NULL); CREATE TABLE IF NOT EXISTS submissions(revision INTEGER PRIMARY KEY,report_id TEXT NOT NULL); CREATE TABLE IF NOT EXISTS credential_intents(id TEXT PRIMARY KEY); PRAGMA user_version=1;")
                try exec("INSERT OR IGNORE INTO draft VALUES(1,0,'{\"kind\":\"problem\",\"text\":\"\",\"revision\":0}')")
                var marker: OpaquePointer?
                guard sqlite3_prepare_v2(handle, "SELECT value FROM meta WHERE key='running'", -1, &marker, nil) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }
                let step = sqlite3_step(marker)
                let unclean = step == SQLITE_ROW
                sqlite3_finalize(marker)
                guard step == SQLITE_ROW || step == SQLITE_DONE else { throw FeedbackFailure.storageUnavailable }
                try exec("INSERT OR REPLACE INTO meta VALUES('running','1')")
                try exec("COMMIT"); wasUnclean = unclean
            } catch { try? exec("ROLLBACK"); throw error }
            resources = FeedbackStoreResources(db: handle, descriptor: lockFD)
        } catch {
            if let handle { sqlite3_close(handle) }
            if lockFD >= 0 { close(lockFD) }
            throw FeedbackFailure.storageUnavailable
        }
    }
    private func statement(_ sql: String, _ args: [String] = []) throws -> OpaquePointer {
        guard let db else { throw FeedbackFailure.storageUnavailable }
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { throw FeedbackFailure.storageUnavailable }
        for (i, a) in args.enumerated() {
            let code = a.withCString { sqlite3_bind_text(s, Int32(i + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard code == SQLITE_OK else { sqlite3_finalize(s); throw FeedbackFailure.storageUnavailable }
        }
        return s
    }
    private func execute(_ sql: String, _ args: [String] = []) throws {
        let s = try statement(sql, args); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_DONE else { throw FeedbackFailure.storageUnavailable }
    }
    private func string(_ s: OpaquePointer, _ column: Int32) -> String {
        guard let pointer = sqlite3_column_text(s, column) else { return "" }
        return String(cString: pointer)
    }
    public func draft() throws -> FeedbackDraft {
        let s = try statement("SELECT payload FROM draft WHERE id=1"); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { throw FeedbackFailure.storageUnavailable }
        do { return try decoder.decode(FeedbackDraft.self, from: Data(string(s, 0).utf8)) }
        catch { throw FeedbackFailure.storageUnavailable }
    }
    public func saveDraft(_ value: FeedbackDraft) throws {
        guard value.text.utf8.count <= 131072, value.revision >= 0, value.revision < Int64.max else { throw FeedbackFailure.invalidText }
        try value.diagnostic?.validate()
        let existing = try draft()
        if value.revision < existing.revision { return }
        guard value.revision != existing.revision || value == existing else { throw FeedbackFailure.conflict }
        let data = try encoder.encode(value)
        try execute("UPDATE draft SET revision=?,payload=? WHERE id=1 AND revision<=?",
                    [String(value.revision), String(decoding: data, as: UTF8.self), String(value.revision)])
    }
    public func submittedID(revision: Int64) throws -> String? {
        let s = try statement("SELECT report_id FROM submissions WHERE revision=?", [String(revision)])
        defer { sqlite3_finalize(s) }
        switch sqlite3_step(s) {
        case SQLITE_ROW: return string(s, 0)
        case SQLITE_DONE: return nil
        default: throw FeedbackFailure.storageUnavailable
        }
    }
    public func enqueue(_ envelope: FeedbackEnvelope, from value: FeedbackDraft) throws -> String {
        if let old = try submittedID(revision: value.revision) { return old }
        try execute("BEGIN IMMEDIATE")
        do {
            guard value.revision < Int64.max, try draft() == value else { throw FeedbackFailure.conflict }
            let s = try statement("SELECT COUNT(*),COALESCE(SUM(length(payload)),0),SUM(CASE WHEN state IN ('queued','deletionQueued','blocked','deletionBlocked') THEN 1 ELSE 0 END) FROM reports")
            defer { sqlite3_finalize(s) }
            guard sqlite3_step(s) == SQLITE_ROW else { throw FeedbackFailure.storageUnavailable }
            guard sqlite3_column_int(s, 0) < 200, sqlite3_column_int(s, 1) < 2 * 1024 * 1024 - 32768,
                  sqlite3_column_int(s, 2) < 20 else { throw FeedbackFailure.capacity }
            let bytes = try envelope.encoded()
            try execute("INSERT INTO reports(id,payload,state,next_attempt,created) VALUES(?,?,'queued',0,?)",
                        [envelope.id, String(decoding: bytes, as: UTF8.self), String(envelope.createdAt)])
            try execute("INSERT INTO submissions VALUES(?,?)", [String(value.revision), envelope.id])
            try execute("DELETE FROM credential_intents WHERE id=?", [envelope.id])
            let fresh = FeedbackDraft(revision: value.revision + 1)
            try execute("UPDATE draft SET revision=?,payload=? WHERE id=1",
                        [String(fresh.revision), String(decoding: try encoder.encode(fresh), as: UTF8.self)])
            // A pruned older revision cannot pass the current-draft equality gate.
            try execute("DELETE FROM submissions WHERE revision<?", [String(max(0, value.revision - 256))])
            try execute("COMMIT"); return envelope.id
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func records() throws -> [FeedbackRecord] {
        let s = try statement("SELECT id,payload,state,attempts,next_attempt,created FROM reports ORDER BY created DESC,id LIMIT 200")
        defer { sqlite3_finalize(s) }
        var result: [FeedbackRecord] = []
        while true {
            let step = sqlite3_step(s)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW, let state = FeedbackLocalState(rawValue: string(s, 2)) else { throw FeedbackFailure.storageUnavailable }
            let bytes = Data(string(s, 1).utf8)
            let envelope: FeedbackEnvelope
            do { envelope = try decoder.decode(FeedbackEnvelope.self, from: bytes) } catch { throw FeedbackFailure.storageUnavailable }
            result.append(FeedbackRecord(id: string(s, 0), envelope: envelope, bytes: bytes, state: state,
                attempts: Int(sqlite3_column_int(s, 3)), nextAttempt: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)),
                created: Date(timeIntervalSince1970: sqlite3_column_double(s, 5))))
        }
    }
    /// Journal only the random report ID before touching Keychain. No secret is
    /// stored here. A failed/abandoned enqueue can be cleaned after restart.
    func registerCredentialIntent(id: String) throws {
        guard UUID(uuidString: id) != nil else { throw FeedbackFailure.conflict }
        try execute("INSERT INTO credential_intents(id) SELECT ? WHERE (SELECT COUNT(*) FROM credential_intents)<32", [id])
        guard sqlite3_changes(db) == 1 else { throw FeedbackFailure.capacity }
    }
    func uncommittedCredentialIDs() throws -> [String] {
        let s = try statement("SELECT id FROM credential_intents WHERE NOT EXISTS(SELECT 1 FROM reports WHERE reports.id=credential_intents.id) LIMIT 32")
        defer { sqlite3_finalize(s) }
        var ids: [String] = []
        while true {
            let step = sqlite3_step(s)
            if step == SQLITE_DONE { return ids }
            guard step == SQLITE_ROW else { throw FeedbackFailure.storageUnavailable }
            ids.append(string(s, 0))
        }
    }
    func finishCredentialCleanup(id: String) throws {
        try execute("DELETE FROM credential_intents WHERE id=? AND NOT EXISTS(SELECT 1 FROM reports WHERE reports.id=credential_intents.id)", [id])
    }
    public func beginAttempt(id: String, expected: FeedbackLocalState) throws -> Bool {
        try execute("UPDATE reports SET attempts=MIN(attempts+1,9999) WHERE id=? AND state=?", [id, expected.rawValue])
        return sqlite3_changes(db) == 1
    }
    public func reschedule(id: String, expected: FeedbackLocalState, after delay: TimeInterval, blocked: Bool = false) throws {
        let state: FeedbackLocalState = blocked ? (expected == .deletionQueued ? .deletionBlocked : .blocked) : expected
        try execute("UPDATE reports SET state=?,next_attempt=? WHERE id=? AND state=?",
                    [state.rawValue, String(Date().addingTimeInterval(max(1, min(86400, delay))).timeIntervalSince1970), id, expected.rawValue])
    }
    public func apply(_ receipt: FeedbackReceipt) throws {
        try receipt.validate(for: receipt.id)
        // Local deletion intent is monotonic across stale POST/GET responses.
        switch receipt.state {
        case "delivered":
            try execute("UPDATE reports SET state='delivered' WHERE id=? AND state IN ('queued','received','blocked')", [receipt.id])
        case "received", "delivery_uncertain":
            try execute("UPDATE reports SET state='received' WHERE id=? AND state='queued'", [receipt.id])
        case "delivery_expired":
            try execute("UPDATE reports SET state='expired' WHERE id=? AND state IN ('queued','received','blocked')", [receipt.id])
        case "deletion_pending":
            try execute("UPDATE reports SET state='deletionPending' WHERE id=? AND state NOT IN ('deleted','cancelled')", [receipt.id])
        case "deleted":
            try execute("UPDATE reports SET state='deleted' WHERE id=? AND state!='cancelled'", [receipt.id])
        default: throw FeedbackFailure.invalidResponse
        }
    }
    public func requestDeletion(id: String) throws {
        // An unavailable credential can block a report before beginAttempt.
        // With no durable attempt there cannot have been HTTP: allow local
        // cancellation even after a failed retry or an older deletion attempt.
        // Received/delivered states and any attempted request still need DELETE.
        try execute("UPDATE reports SET state=CASE WHEN attempts=0 AND state IN ('queued','blocked','deletionQueued','deletionBlocked') THEN 'cancelled' ELSE 'deletionQueued' END,next_attempt=0 WHERE id=? AND state NOT IN ('deleted','cancelled','deletionPending')", [id])
    }
    public func forgetResolved(id: String) throws {
        try execute("DELETE FROM reports WHERE id=? AND state IN ('deleted','cancelled')", [id])
        guard sqlite3_changes(db) == 1 else { throw FeedbackFailure.conflict }
    }
    public func closeForTesting(clean: Bool) throws {
        if clean { try markClean() }
        if let db { guard sqlite3_close(db) == SQLITE_OK else { throw FeedbackFailure.storageUnavailable }; self.db = nil }
        if descriptor >= 0 { close(descriptor); descriptor = -1 }
    }
    public func markClean() throws { try execute("DELETE FROM meta WHERE key='running'") }
}
