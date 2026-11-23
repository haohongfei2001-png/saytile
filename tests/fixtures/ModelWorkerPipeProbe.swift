import Darwin
import Foundation

@main struct Probe {
    static func packet(_ input: Data) -> Data {
        var n = UInt32(input.count).littleEndian
        var wire = withUnsafeBytes(of: &n) { Data($0) }
        wire.append(input); return wire
    }

    static func main() throws {
        let p = Pipe()
        let send = p.fileHandleForWriting
        var reader = PCMFrameReader(descriptor: p.fileHandleForReading.fileDescriptor)
        let first = Data([0x11, 0x22]), second = Data([0x33, 0x44, 0x55, 0x66])
        let t = ContinuousClock.now
        func check(_ condition: Bool) { precondition(condition) }
        check(try !reader.hasNextFrameNow())
        let a = packet(first), b = packet(second)
        try send.write(contentsOf: a.prefix(3))
        check(try !reader.hasNextFrameNow())
        try send.write(contentsOf: a.dropFirst(3).prefix(2))
        check(try !reader.hasNextFrameNow())
        try send.write(contentsOf: a.suffix(1) + b + packet(Data()) + a + packet(Data()))
        check(try reader.hasNextFrameNow())
        check(try reader.hasNextFrameNow())
        check(try reader.next() == first)
        check(try reader.next() == second)
        check(try reader.hasNextFrameNow())
        check(try reader.next() == Data())
        check(try reader.next() == first)
        check(try reader.next() == Data())
        check(try !reader.hasNextFrameNow())
        try send.close()
        check(try reader.next() == nil)
        check(try !reader.hasNextFrameNow())
        check(t.duration(to: .now) < .seconds(2))
        for (bad, expected) in [(Data([0x02]), "truncated"), (Data([0x03,0,0,0]), "invalidFrame"),
                               (Data([2,0,1,0]), "invalidFrame"),(Data([4,0,0,0,1]),"truncated")] {
            let p = Pipe(); try p.fileHandleForWriting.write(contentsOf: bad); try p.fileHandleForWriting.close()
            var r = PCMFrameReader(descriptor: p.fileHandleForReading.fileDescriptor)
            do { _ = try r.next(); preconditionFailure() }
            catch let error as WorkerError { check(String(describing: error) == expected) }
        }
        let split = Pipe()
        let big = Data((0..<65_536).map { UInt8(truncatingIfNeeded: $0) })
        let wire = packet(big) + packet(Data()) + packet(second) + packet(Data())
        DispatchQueue.global().async {
            for i in stride(from: 0, to: wire.count, by: 1_001) {
                try! split.fileHandleForWriting.write(contentsOf: wire[i..<min(i+1_001,wire.count)])
            }
            try! split.fileHandleForWriting.close()
        }
        var r = PCMFrameReader(descriptor: split.fileHandleForReading.fileDescriptor)
        check(try r.next() == big); check(try r.next() == Data()); check(try r.next() == second)
        check(try r.next() == Data()); check(try r.next() == nil)
        print("PASS nonblocking empty/header/body; repeated peek; EOS; adjacent utterances; 65,536B split packet; invalid length and truncated EOF")
    }
}
