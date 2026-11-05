import Testing
import Foundation
import CAudio
@testable import SaytileKit

private final class SyncFault: @unchecked Sendable {
    let lock = NSLock()
    var checkpoints = 0
    func synchronize(_ handle: FileHandle) throws {
        if try handle.offset() == 44 {
            lock.lock(); checkpoints += 1; let reject = checkpoints > 1; lock.unlock()
            if reject { throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)) }
        }
        try handle.synchronize()
    }
}
@Suite("Capture storage failures")
struct AudioStorageFailureTests {
    @Test func invalidAudioDirectorySealsRecordInsteadOfLeavingItActive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-directory-fault-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        try FileManager.default.removeItem(at: store.audioDirectory)
        try Data([0]).write(to: store.audioDirectory)
        let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 32_000), sampleRate: 16_000, recognitionEnabled: false, update: { _, _ in }, failed: { _ in })
        do { try await worker.beginUtterance(); Issue.record("Directory failure must throw") } catch {}
        let records = try await store.listRecordings()
        #expect(records.count == 1)
        #expect(records.first?.isRecording == false)
        #expect(records.first?.audioState == .missing)
        #expect(records.first?.lastError != nil)
    }
    @Test func failedFinalSyncKeepsOnlyPublishedDurableAudioAndPreservesText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-sync-fault-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let fault = SyncFault()
        let io = PCMJournal.IO(synchronize: { try fault.synchronize($0) })
        let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 32_000), sampleRate: 16_000, recognitionEnabled: false, journalIO: io, update: { _, _ in }, failed: { _ in })
        try await worker.beginUtterance()
        try await worker.append(Data(repeating: 1, count: 32_000))
        let id = try #require(try await store.listRecordings().first?.id)
        _ = try await store.saveEdit(recordingID: id, text: "保留我的文字")
        try await worker.append(Data(repeating: 2, count: 1_600))
        do { try await worker.endUtterance(); Issue.record("Sync failure must throw") } catch {}
        let record = try #require(try await store.recording(id: id))
        #expect(!record.isRecording)
        #expect(record.audioState == .available)
        #expect(record.duration == 1)
        #expect(record.text == "保留我的文字")
        #expect(record.lastError?.contains("未确认的尾部") == true)
        #expect(record.recognitionState == .failed)
    }
    @Test func realtimeWriteFailureStopsWorkerAndSealsEmptyRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-write-fault-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let ring = try AudioRing(capacity: 32_000)
        let io = PCMJournal.IO(write: { _, data in
            if data.count != 44 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)) }
        })
        let worker = try CaptureWorker(store: store, ring: ring, sampleRate: 16_000, recognitionEnabled: false, journalIO: io, update: { _, _ in }, failed: { _ in })
        var tone = (0..<3_200).map { i in Float(0.3 * sin(2 * Double.pi * 120 * Double(i) / 16_000) + 0.12 * sin(2 * Double.pi * 660 * Double(i) / 16_000)) }
        tone.withUnsafeMutableBufferPointer { samples in
            var pointer = samples.baseAddress
            withUnsafePointer(to: &pointer) { st_ring_write(ring.pointer, $0, 1, 3_200) }
        }
        await worker.start()
        try await Task.sleep(for: .milliseconds(200))
        await worker.stop()
        let records = try await store.listRecordings()
        #expect(records.count == 1)
        #expect(records.first?.isRecording == false)
        #expect(records.first?.audioState == .missing)
        #expect(records.first?.duration == 0)
    }
}
