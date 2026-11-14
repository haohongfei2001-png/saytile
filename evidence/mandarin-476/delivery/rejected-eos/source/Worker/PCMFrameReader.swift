import Darwin
import Foundation

enum WorkerError: Error { case invalidFrame, truncated, configuration }

/// One reader owns this framed pipe. An incomplete header or payload remains
/// buffered if no more bytes are ready. Zero-length payload is the segment EOS.
struct PCMFrameReader {
    let descriptor: Int32
    private var pending = Data()
    private var buffer = [UInt8](repeating: 0, count: 16_384)
    private var offset = 0
    private var endOfPipe = false
    private var prefetched: Data?

    init(descriptor: Int32) { self.descriptor = descriptor }

    mutating func hasNextFrameNow() throws -> Bool {
        if prefetched == nil { prefetched = try readFrame(wait: false) }
        return prefetched != nil
    }

    mutating func next() throws -> Data? {
        if let prefetched {
            self.prefetched = nil
            return prefetched
        }
        return try readFrame(wait: true)
    }

    private mutating func readFrame(wait: Bool) throws -> Data? {
        while true {
            if pending.count - offset >= 4 {
                let size = Int(pending.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
                })
                guard size <= 65_536, size.isMultiple(of: 2) else { throw WorkerError.invalidFrame }
                if pending.count - offset - 4 >= size {
                    let start = offset + 4
                    offset = start + size
                    return pending.subdata(in: start..<offset)
                }
            }
            if endOfPipe {
                guard offset == pending.count else { throw WorkerError.truncated }
                return nil
            }
            if !wait {
                var watched = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                let ready = poll(&watched, 1, 0)
                if ready < 0 && errno == EINTR { continue }
                guard ready >= 0 else { throw WorkerError.truncated }
                if ready == 0 { return nil }
            }
            if offset > 0 {
                pending = pending.subdata(in: offset..<pending.count)
                offset = 0
            }
            let fd = descriptor
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw WorkerError.truncated }
            if count == 0 { endOfPipe = true }
            else { pending.append(contentsOf: buffer.prefix(count)) }
        }
    }
}
