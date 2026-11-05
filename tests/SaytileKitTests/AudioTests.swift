import Testing
import Foundation
import CAudio
@testable import SaytileKit

@Suite("Audio journal, bounded ring and VAD")
struct AudioTests {
    @Test func testRingKeepsOrderingAndRejectsOverflowWithoutOverwrite() throws {
        let ring = try #require(st_ring_create(8)); defer { st_ring_destroy(ring) }
        var input: [Float] = [1, 2, 3, 4, 5, 6]
        input.withUnsafeMutableBufferPointer { samples in
            var channels: [UnsafeMutablePointer<Float>?] = [samples.baseAddress]
            channels.withUnsafeMutableBytes { st_ring_write(ring, $0.baseAddress, 1, 6) }
            channels.withUnsafeMutableBytes { st_ring_write(ring, $0.baseAddress, 1, 6) }
        }
        #expect(st_ring_dropped(ring) == 6)
        var output = [Float](repeating: 0, count: 8)
        let n = output.withUnsafeMutableBufferPointer { st_ring_read(ring, $0.baseAddress, 8) }
        #expect(n == 6); #expect(Array(output.prefix(6)) == input)
        #expect(output.withUnsafeMutableBufferPointer { st_ring_read(ring, $0.baseAddress, 8) } == 0)
    }
    @Test func testRingWrapsAndDownmixesStereo() throws {
        let ring = try #require(st_ring_create(4)); defer { st_ring_destroy(ring) }
        var left: [Float] = [1, 3, 5]; var right: [Float] = [3, 5, 7]
        func write() { left.withUnsafeMutableBufferPointer { a in right.withUnsafeMutableBufferPointer { b in
            var pointers = [a.baseAddress, b.baseAddress]
            pointers.withUnsafeMutableBytes { st_ring_write(ring, $0.baseAddress, 2, 3) }
        } } }
        var output = [Float](repeating: 0, count: 3)
        write(); _ = output.withUnsafeMutableBufferPointer { st_ring_read(ring, $0.baseAddress, 3) }
        write(); _ = output.withUnsafeMutableBufferPointer { st_ring_read(ring, $0.baseAddress, 3) }
        #expect(output == [2, 4, 6]); #expect(st_ring_dropped(ring) == 0)
    }
    @Test func testSilenceDoesNotCreateRecordings() throws {
        let segmenter = try VoiceSegmenter()
        for _ in 0..<100 { #expect(segmenter.accept(Data(repeating: 0, count: 6_400)).isEmpty) }
        #expect(!segmenter.speaking)
    }
    @Test func testCheckpointAndInterruptedTailRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-audio-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID(); let journal = try PCMJournal(directory: directory, recordingID: id)
        try journal.openChunk(); try journal.append(Data(repeating: 1, count: 32_000)); try journal.checkpoint()
        let url = directory.appendingPathComponent(journal.relativePath)
        let durable = try Data(contentsOf: url)
        #expect(durable.count == 32_044); #expect(String(data: durable.prefix(4), encoding: .utf8) == "RIFF")
        try journal.append(Data(repeating: 2, count: 4_001))
        // Simulate an abrupt process death after an odd incomplete PCM frame. Header is stale.
        let recovered = try PCMJournal.repair(url)
        #expect(recovered == 18_000)
        #expect(try Data(contentsOf: url).count == 36_044)
    }
    @Test func testFifteenSecondRotationBoundary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-audio-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try PCMJournal(directory: directory, recordingID: UUID()); try journal.openChunk()
        try journal.append(Data(repeating: 0, count: 479_360)); #expect(!journal.needsRotation)
        try journal.append(Data(repeating: 0, count: 640)); #expect(journal.needsRotation)
        try journal.closeChunk(); let oldPath = journal.relativePath; try journal.openChunk()
        #expect(oldPath != journal.relativePath); #expect(journal.frames == 0)
        try journal.closeChunk()
    }
}
