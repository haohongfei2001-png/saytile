import Foundation
import Darwin

/// Held for the complete lifetime of the writable store; the kernel releases it on crash.
final class StoreProcessLock: @unchecked Sendable {
    private var descriptor: Int32
    init(directory: URL) throws {
        let path = directory.appendingPathComponent(".writer-lock").path
        descriptor = Darwin.open(path,O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,0o600)
        guard descriptor >= 0 else { throw StoreError.database("无法锁定资料目录") }
        guard flock(descriptor,LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor); descriptor = -1
            throw StoreError.database("这份资料已由另一个 Saytile 实例打开。请关闭另一个实例后重试。")
        }
    }
    func close() {
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }
    deinit { close() }
}

/// Reject aliases at owned storage leaves, while permitting standard parent aliases
/// such as /tmp -> /private/tmp.
enum StorePath {
    static func rejectSymbolicLink(_ url: URL) throws {
        var information = stat()
        let result = Darwin.lstat(url.path,&information)
        if result == 0,information.st_mode & S_IFMT == S_IFLNK { throw StoreError.invalidPath }
        if result != 0,errno != ENOENT { throw StoreError.invalidPath }
    }
}
