import Foundation
import Darwin

extension SaytileStore {
    /// Exact recording-relative PCM16 sample range from Store-published durable chunks.
    /// Each call is bounded to 1 MiB; long consumers advance startFrame, never load a recording.
    public func readPCMRange(ticket: RecognitionTicket, startFrame: Int64, frameCount: Int) throws -> Data {
        guard try isRecognitionCurrent(ticket: ticket) else { throw FusionError.staleGeneration }
        guard startFrame >= 0, frameCount > 0, frameCount <= 524_288,
              startFrame <= Int64.max - Int64(frameCount) else { throw StoreError.invalidFrames }
        let lease = try acquireAudioLease(recordingID: ticket.recordingID)
        defer { try? releaseAudioLease(lease) }
        let chunks = try audioChunks(recordingID: ticket.recordingID)
        let end = startFrame + Int64(frameCount)
        var offset: Int64 = 0, output = Data()
        output.reserveCapacity(frameCount * 2)
        for (ordinal, chunk) in chunks.enumerated() {
            guard chunk.ordinal == ordinal else { throw StoreError.invalidFrames }
            guard offset <= Int64.max - chunk.frames else { throw StoreError.invalidFrames }
            let chunkEnd = offset + chunk.frames
            defer { offset = chunkEnd }
            if chunkEnd <= startFrame { continue }
            if offset >= end { break }
            let localStart = max(startFrame, offset) - offset
            let count = min(end, chunkEnd) - offset - localStart
            guard count > 0 else { continue }
            let url = try audioURL(for: chunk)
            let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw StoreError.audioUnavailable }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            guard let header = try handle.read(upToCount: 44), header.count == 44,
                  header.prefix(4) == Data("RIFF".utf8), header.subdata(in: 8..<36) == PCMJournal.header(frames: 0).subdata(in: 8..<36),
                  header.subdata(in: 36..<40) == Data("data".utf8) else { throw StoreError.audioUnavailable }
            let declaredBytes = header[40..<44].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
            guard declaredBytes % 2 == 0, declaredBytes / 2 >= UInt64(chunk.frames) else { throw StoreError.audioUnavailable }
            try handle.seek(toOffset: UInt64(44 + localStart * 2))
            guard let bytes = try handle.read(upToCount: Int(count * 2)), bytes.count == Int(count * 2) else { throw StoreError.audioUnavailable }
            output.append(bytes)
        }
        // Never clamp a request into the nondurable tail or return partial audio as complete.
        guard output.count == frameCount * 2 else { throw StoreError.invalidFrames }
        return output
    }
}
