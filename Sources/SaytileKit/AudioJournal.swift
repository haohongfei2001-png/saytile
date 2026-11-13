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
        var synchronize: @Sendable (FileHandle) throws -> Void = { try PCMJournal.flushToDisk($0) }
        static let live = IO()
    }
    let directory: URL
    let recordingID: UUID
    private let io: IO
    private let recordingDirectoryDescriptor: Int32
    private var file: FileHandle?
    private(set) var relativePath = ""
    private(set) var frames: Int64 = 0
    private var lastCheckpoint: Int64 = 0
    var durableFrames: Int64 { lastCheckpoint }
    var isOpen: Bool { file != nil }
    init(directory: URL, recordingID: UUID, io: IO = .live) throws {
        self.directory = directory; self.recordingID = recordingID
        self.io = io
        let parent = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(parent) }
        if mkdirat(parent, recordingID.uuidString, 0o700) != 0 && errno != EEXIST {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let owned = openat(parent, recordingID.uuidString, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard owned >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard fsync(parent) == 0 else { let code = errno; Darwin.close(owned); throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
        recordingDirectoryDescriptor = owned
    }
    func openChunk() throws {
        frames = 0; lastCheckpoint = 0
        let filename = UUID().uuidString + ".wav"
        relativePath = "\(recordingID.uuidString)/\(filename)"
        let descriptor = openat(recordingDirectoryDescriptor, filename, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        file = handle
        try io.write(handle, Self.header(frames: 0))
        try io.synchronize(handle)
        guard fsync(recordingDirectoryDescriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        try handle.seekToEnd()
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
    func closeChunk() throws {
        if frames != lastCheckpoint { try checkpoint() }
        try file?.close()
        file = nil
    }

    // fsync alone can leave completed writes in a drive's volatile cache on macOS.
    // Request a media flush at checkpoints, never on individual PCM frames.
    private static func flushToDisk(_ file: FileHandle) throws {
        if Darwin.fcntl(file.fileDescriptor, F_FULLFSYNC) == 0 { return }
        let code = errno
        if code == ENOTSUP || code == EINVAL || code == ENOTTY {
            // Some mounted filesystems only implement the portable durability primitive.
            try file.synchronize()
            return
        }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
    func abandonOpenHandle() { try? file?.close(); file = nil }
    deinit { try? file?.close(); Darwin.close(recordingDirectoryDescriptor) }
    static func header(frames: Int64) -> Data {
        var data = Data()
        func text(_ s: String) { data.append(contentsOf: s.utf8) }
        func u16(_ n: UInt16) { var v = n.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u32(_ n: UInt32) { var v = n.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(frames * 2 + 36)); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(16_000); u32(32_000); u16(2); u16(16); text("data"); u32(UInt32(frames * 2))
        return data
    }
    enum RepairFailure: LocalizedError {
        case incompleteHeader, fileTooLarge
        var errorDescription: String? {
            switch self {
            case .incompleteHeader: "原音头不完整"
            case .fileTooLarge: "原音文件超过 WAV 容量上限，拒绝损坏的文件"
            }
        }
    }
    static func repair(_ url: URL, indexedFrames: Int64? = nil) throws -> Int64 {
        // An intact file needs only read permission. Request write access only
        // when a recovered crash tail or stale header actually requires repair.
        let reader = try FileHandle(forReadingFrom: url); defer { try? reader.close() }
        let size = try reader.seekToEnd()
        guard size >= 44 else { throw RepairFailure.incompleteHeader }
        guard size - 8 <= UInt64(UInt32.max) else { throw RepairFailure.fileTooLarge }
        let frames = Int64((size - 44) / 2)
        try reader.seek(toOffset: 0)
        let currentHeader = try reader.read(upToCount: 44)
        if size == UInt64(44 + frames * 2), currentHeader == header(frames: frames) {
            // A failed media flush can still leave a readable updated WAV header.
            // Confirm newly discovered frames before raising SQLite's durable watermark.
            if let indexedFrames, indexedFrames != frames { try flushToDisk(reader) }
            return frames
        }
        let handle = try FileHandle(forUpdating: url); defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(44 + frames * 2))
        try handle.seek(toOffset: 0); try handle.write(contentsOf: header(frames: frames)); try flushToDisk(handle)
        return frames
    }
}

/// WebRTC consumes 20 ms frames. A one-second pre-roll protects speech onset.
final class VoiceSegmenter {
    // Keep the active local recognizer through a short thinking pause.
    static let localPauseFrames = 75
    enum Event { case begin([Data], sample: Int64), audio(Data), end(sample: Int64) }
    private let vad: OpaquePointer
    private var pending = Data()
    private var preRoll: [Data] = []
    private(set) var speaking = false
    private(set) var receivedSamples: Int64 = 0
    private var frameEnd: Int64 = 0
    private var possibleStart: Int64 = 0
    private var speechVotes = 0
    private var silence = 0
    private var activeFrames = 0
    private let endSilenceFrames: Int
    private var activeMaximum = 1500
    private let maximumFrames: Int
    init(endSilenceFrames: Int = VoiceSegmenter.localPauseFrames, maximumFrames: Int = 1_500) throws {
        guard let vad = st_vad_create() else { throw AudioFailure.message("VAD 初始化失败") }
        self.vad = vad; self.endSilenceFrames = max(1, endSilenceFrames); self.maximumFrames = max(1, maximumFrames)
    }
    deinit { st_vad_destroy(vad) }
    func accept(_ data: Data, nextMaximumFrames: Int? = nil) -> [Event] {
        receivedSamples += Int64(data.count / 2)
        pending.append(data); var events: [Event] = []
        while pending.count >= 640 {
            let frame = Data(pending.prefix(640)); pending.removeFirst(640)
            frameEnd += 320
            let decision = frame.withUnsafeBytes { st_vad_process(vad, $0.bindMemory(to: Int16.self).baseAddress!, 320) }
            if !speaking {
                preRoll.append(frame); if preRoll.count > 50 { preRoll.removeFirst() }
                let voiced = decision == STVoiceDetected
                if voiced && speechVotes == 0 { possibleStart = frameEnd - 320 }
                speechVotes = voiced ? speechVotes + 1 : max(0, speechVotes - 1)
                if speechVotes >= 3 { activeMaximum = nextMaximumFrames ?? maximumFrames; speaking = true; silence = 0; activeFrames = 0; events.append(.begin(preRoll, sample: possibleStart)); preRoll.removeAll(keepingCapacity: true) }
            } else {
                // A duration limit rotates an active recognizer; it is not a
                // new speech onset. Keep the old journal open through quiet
                // or a sub-frame EOF and move only on the next voiced frame.
                if activeFrames >= activeMaximum && decision == STVoiceDetected {
                    let boundary = frameEnd - 320
                    events.append(.end(sample: boundary - Int64(silence) * 320))
                    events.append(.begin([frame], sample: boundary))
                    activeMaximum = nextMaximumFrames ?? maximumFrames
                    activeFrames = 1
                    silence = 0
                    continue
                }
                events.append(.audio(frame)); activeFrames += 1
                silence = decision == STVoiceQuiet ? silence + 1 : 0
                if silence >= endSilenceFrames {
                    events.append(.end(sample: frameEnd - Int64(silence) * 320))
                    speaking = false; speechVotes = 0; silence = 0
                }
            }
        }
        // Data.removeFirst advances a slice without releasing its consumed
        // allocation. Keep only the incomplete 20 ms frame, not the lifetime
        // PCM prefix. The raw-byte initializer guarantees an independent copy.
        pending = pending.withUnsafeBytes { Data($0) }
        return events
    }
    func finish() -> [Event] {
        defer { pending.removeAll(); preRoll.removeAll(); speaking = false; speechVotes = 0; silence = 0 }
        guard speaking else { return [] }
        let completeBytes = pending.count - pending.count % 2
        let ending = Event.end(sample: silence == 0 ? receivedSamples : frameEnd - Int64(silence) * 320)
        return completeBytes > 0 ? [.audio(Data(pending.prefix(completeBytes))), ending] : [ending]
    }
}
