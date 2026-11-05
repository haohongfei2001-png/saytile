import Foundation
import CAudio
import Darwin

public enum AudioFailure: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case let .message(message) = self { message } else { nil } }
}

/// Independent PCM16 WAV files. Header and audio are synchronized before publishing coverage.
final class PCMJournal {
    struct IO: Sendable {
        var write: @Sendable (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) }
        var synchronize: @Sendable (FileHandle) throws -> Void = { try $0.synchronize() }
        static let live = IO()
    }
    let directory: URL
    let recordingID: UUID
    private let io: IO
    private var file: FileHandle?
    private(set) var relativePath = ""
    private(set) var frames: Int64 = 0
    private var lastCheckpoint: Int64 = 0
    var durableFrames: Int64 { lastCheckpoint }
    var isOpen: Bool { file != nil }
    init(directory: URL, recordingID: UUID, io: IO = .live) throws {
        self.directory = directory; self.recordingID = recordingID
        self.io = io
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(recordingID.uuidString), withIntermediateDirectories: true)
        try Self.synchronizeDirectory(directory)
    }
    func openChunk() throws {
        // A failed rotation must never attribute the previous file's watermark
        // to the new pathname.
        frames = 0; lastCheckpoint = 0
        relativePath = "\(recordingID.uuidString)/\(UUID().uuidString).wav"
        let url = directory.appendingPathComponent(relativePath)
        guard FileManager.default.createFile(atPath: url.path, contents: Self.header(frames: 0)) else { throw AudioFailure.message("无法创建原音文件") }
        file = try FileHandle(forUpdating: url)
        if let file { try io.synchronize(file) }
        // Persist the directory entry as well as the new file before registering it.
        try Self.synchronizeDirectory(url.deletingLastPathComponent())
        try file?.seekToEnd()
    }
    private static func synchronizeDirectory(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    func append(_ pcm: Data) throws {
        guard let file else { throw AudioFailure.message("原音文件尚未打开") }
        try io.write(file, pcm); frames += Int64(pcm.count / 2)
    }
    var needsCheckpoint: Bool { frames - lastCheckpoint >= 16_000 }
    var needsRotation: Bool { frames >= 240_000 }
    func checkpoint() throws {
        guard let file else { return }
        try file.seek(toOffset: 0); try io.write(file, Self.header(frames: frames))
        try io.synchronize(file); lastCheckpoint = frames; try file.seekToEnd()
    }
    func closeChunk() throws { try checkpoint(); try file?.close(); file = nil }
    func abandonOpenHandle() { try? file?.close(); file = nil }
    deinit { try? file?.close() }
    static func header(frames: Int64) -> Data {
        var data = Data()
        func text(_ s: String) { data.append(contentsOf: s.utf8) }
        func u16(_ n: UInt16) { var v = n.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u32(_ n: UInt32) { var v = n.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(frames * 2 + 36)); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(16_000); u32(32_000); u16(2); u16(16); text("data"); u32(UInt32(frames * 2))
        return data
    }
    static func repair(_ url: URL) throws -> Int64 {
        let handle = try FileHandle(forUpdating: url); defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size >= 44 else { throw AudioFailure.message("原音头不完整") }
        let frames = Int64((size - 44) / 2)
        try handle.seek(toOffset: 0)
        let currentHeader = try handle.read(upToCount: 44)
        if size == UInt64(44 + frames * 2), currentHeader == header(frames: frames) { return frames }
        try handle.truncate(atOffset: UInt64(44 + frames * 2))
        try handle.seek(toOffset: 0); try handle.write(contentsOf: header(frames: frames)); try handle.synchronize()
        return frames
    }
}

/// WebRTC's mature 20ms VAD, with 1 second pre-roll and 800ms end silence.
final class VoiceSegmenter {
    enum Event { case begin([Data]), audio(Data), end }
    private let vad: OpaquePointer
    private var pending = Data()
    private var preRoll: [Data] = []
    private(set) var speaking = false
    private var speechVotes = 0
    private var silence = 0
    private var activeFrames = 0
    init() throws { guard let vad = st_vad_create() else { throw AudioFailure.message("VAD 初始化失败") }; self.vad = vad }
    deinit { st_vad_destroy(vad) }
    func accept(_ data: Data) -> [Event] {
        pending.append(data); var events: [Event] = []
        while pending.count >= 640 {
            let frame = Data(pending.prefix(640)); pending.removeFirst(640)
            let voiced = frame.withUnsafeBytes { st_vad_process(vad, $0.bindMemory(to: Int16.self).baseAddress!, 320) == 1 }
            if !speaking {
                preRoll.append(frame); if preRoll.count > 50 { preRoll.removeFirst() }
                speechVotes = voiced ? speechVotes + 1 : max(0, speechVotes - 1)
                if speechVotes >= 3 { speaking = true; silence = 0; activeFrames = 0; events.append(.begin(preRoll)); preRoll.removeAll(keepingCapacity: true) }
            } else {
                events.append(.audio(frame)); activeFrames += 1
                silence = voiced ? 0 : silence + 1
                // Rotate visual / ASR units at 30s while maintaining uninterrupted capture.
                if silence >= 40 || activeFrames >= 1_500 {
                    speaking = false; speechVotes = 0; silence = 0; events.append(.end)
                }
            }
        }
        return events
    }
    func finish() -> [Event] {
        defer { pending.removeAll(); preRoll.removeAll(); speaking = false; speechVotes = 0; silence = 0 }
        guard speaking else { return [] }
        let completeBytes = pending.count - pending.count % 2
        return completeBytes > 0 ? [.audio(Data(pending.prefix(completeBytes))), .end] : [.end]
    }
}
