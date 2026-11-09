import Foundation
import CSQLite

// The connection is owned by SaytileStore. No handle escapes its actor.
final class StoreDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    init(url: URL, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE)
        let result = sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else { throw StoreError.database("无法打开 SQLite (\(result))") }
        sqlite3_busy_timeout(handle, 5000)
    }
    func configureForWriting() throws {
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        try execute("PRAGMA foreign_keys=ON")
    }
    func close() throws {
        guard let connection = handle else { return }
        guard sqlite3_close(connection) == SQLITE_OK else { throw error() }
        handle = nil
    }
    deinit { sqlite3_close(handle) }
    enum Value { case text(String), int(Int64), double(Double), null }
    func execute(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else { throw error() }
    }
    func script(_ sql: String) throws {
        guard handle != nil else { throw StoreError.database("资料库已关闭") }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }
    func rows(_ sql: String, _ values: [Value] = []) throws -> [[String:String]] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [[String:String]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW else { throw error() }
            var row: [String:String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString:sqlite3_column_name(statement,index))
                switch sqlite3_column_type(statement,index) {
                case SQLITE_NULL:
                    continue
                case SQLITE_INTEGER:
                    row[name] = String(sqlite3_column_int64(statement,index))
                case SQLITE_FLOAT:
                    // Older SQLite text conversion rounds REAL values to 15 digits.
                    // Swift's Double description preserves the exact stored value.
                    row[name] = String(sqlite3_column_double(statement,index))
                default:
                    let length = Int(sqlite3_column_bytes(statement,index))
                    let bytes = sqlite3_column_text(statement,index)!
                    row[name] = String(decoding:UnsafeBufferPointer(start:bytes,count:length),as:UTF8.self)
                }
            }
            result.append(row)
        }
    }
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try body(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func error() -> StoreError { .database(handle.map { String(cString:sqlite3_errmsg($0)) } ?? "连接关闭") }
    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        guard handle != nil else { throw StoreError.database("资料库已关闭") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle,sql,-1,&statement,nil) == SQLITE_OK, let statement else { throw error() }
        for (offset,value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .text(let text): code = sqlite3_bind_text(statement,index,text,Int32(text.utf8.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self))
            case .int(let value): code = sqlite3_bind_int64(statement,index,value)
            case .double(let value): code = sqlite3_bind_double(statement,index,value)
            case .null: code = sqlite3_bind_null(statement,index)
            }
            guard code == SQLITE_OK else { sqlite3_finalize(statement); throw error() }
        }
        return statement
    }
}
