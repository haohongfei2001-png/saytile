import Testing
import Foundation
@testable import SaytileKit

@Suite("Audio file boundary recovery")
struct AudioJournalBoundaryTests {
    @Test func oversizedSparseWAVIsRejectedBeforeHeaderConversion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-large-wave-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("large.wav")
        try PCMJournal.header(frames: 0).write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(UInt32.max) + 4096); try handle.close()
        #expect(throws: (any Error).self) { try PCMJournal.repair(url) }
        let reader = try FileHandle(forReadingFrom: url); defer { try? reader.close() }
        #expect(try reader.read(upToCount: 44) == PCMJournal.header(frames: 0))
    }
    @Test func recordDirectorySymlinkCannotCreateFileOutsideAudioRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-audio-link-\(UUID())")
        let audio = root.appendingPathComponent("audio"), outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try FileManager.default.createSymbolicLink(at: audio.appendingPathComponent(id.uuidString), withDestinationURL: outside)
        #expect(throws: (any Error).self) { _ = try PCMJournal(directory: audio, recordingID: id) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}
