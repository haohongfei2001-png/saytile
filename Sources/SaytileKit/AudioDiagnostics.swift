import Foundation
@preconcurrency import AVFoundation

/// Offline fixture import used by acceptance tests. Never opens a microphone or external application.
public enum AudioDiagnostics {
    @discardableResult public static func transcribeFixture(url: URL, store: SaytileStore, realtime: Bool = false, event: @escaping @Sendable (SpeechTimingEvent) -> Void = { _ in }) async throws -> UUID {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else { throw AudioFailure.message("无法转换测试音频") }
        let record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: 0)
        let ticket = try await store.beginRecognition(recordingID: record.id)
        let session = LiveSpeechSession(store: store, ticket: ticket, event: event)
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1_024)!
            try file.read(into: buffer)
            let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: UInt32(ceil(1_024 * 16_000 / file.processingFormat.sampleRate) + 32))!
            var supplied = false; var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return buffer
            }
            if status == .error { throw error ?? AudioFailure.message("测试音频转换失败") as NSError }
            let pcm = Data(bytes: output.int16ChannelData![0], count: Int(output.frameLength) * 2)
            try journal.append(pcm)
            if journal.needsCheckpoint { try journal.checkpoint(); try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: journal.frames) }
            session.append(pcm)
            if journal.needsRotation { try journal.closeChunk(); try journal.openChunk(); try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: 0) }
            try await Task.sleep(for: .seconds(realtime ? Double(buffer.frameLength) / file.processingFormat.sampleRate : 0.03))
        }
        try journal.closeChunk(); try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: journal.frames)
        try await store.finishRecording(id: record.id); session.finish(); await session.wait()
        return record.id
    }
    /// Repairs only DB-owned files, after deletion intents. Unknown orphans are never reimported.
    public static func recoverAudio(store: SaytileStore) async throws -> Int {
        try await store.recoverPendingDeletions()
        var count = 0; var offset = 0
        while true {
            let recordings = try await store.listRecordings(limit: 200, offset: offset)
            if recordings.isEmpty { break }
            for record in recordings where record.audioState == .available && !record.isRecording {
                let chunks = try await store.audioChunks(recordingID: record.id)
                guard !chunks.isEmpty else {
                    try await store.markAudioMissing(recordingID:record.id,message:"上次采集在原音登记前中断，已有文字已保留")
                    continue
                }
                for chunk in chunks {
                    do {
                        // Keep ownership/path validation before opening the file, but
                        // isolate a single inaccessible recording from healthy ones.
                        let url = try await store.audioURL(for: chunk)
                        let frames = try PCMJournal.repair(url)
                        if frames != chunk.frames { try await store.reconcileAudioChunk(recordingID: record.id, path: chunk.relativePath, actualFrames: frames); count += 1 }
                    } catch let error as PCMJournal.RepairFailure {
                        try await store.markAudioMissing(recordingID: record.id, message: "原音文件不完整，文字已保留：\(error.localizedDescription)")
                        break
                    } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                        // A false fileExists result can also mean access was denied.
                        // Only an explicit missing-file error proves absence.
                        try await store.markAudioMissing(recordingID: record.id, message: "部分原音文件缺失，文字已保留")
                        break
                    } catch {
                        // Permission, disk-space and SQLite failures can be transient.
                        // Do not permanently hide a file that is still owned and present.
                        try await store.recordAudioRecoveryFailure(recordingID: record.id,
                            message: "原音恢复暂未完成，文件和文字已保留：\(error.localizedDescription)")
                        break
                    }
                }
            }
            offset += recordings.count
        }
        return count
    }
}

extension AudioDiagnostics {
    /// Runs the production VAD / journal / SQLite path at accelerated speed, with ASR unavailable.
    /// Useful for deterministic longevity checks; does not claim real-time or microphone verification.
    public static func exerciseCaptureFixture(url: URL, repetitions: Int, store: SaytileStore) async throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else { throw AudioFailure.message("无法转换测试音频") }
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length))!
        try file.read(into: input)
        let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: UInt32(ceil(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 64))!
        var supplied = false; var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        if status == .error { throw error ?? AudioFailure.message("测试音频转换失败") as NSError }
        let pcm = Data(bytes: output.int16ChannelData![0], count: Int(output.frameLength) * 2)
        let ring = try AudioRing(capacity: 64_000)
        let worker = try CaptureWorker(store: store, ring: ring, sampleRate: 16_000, recognitionEnabled: false, update: { _, _ in }, failed: { _ in })
        for _ in 0..<repetitions {
            for offset in stride(from: 0, to: pcm.count, by: 3_200) { try await worker.acceptPCM(pcm.subdata(in: offset..<min(offset + 3_200, pcm.count))) }
            try await worker.acceptPCM(Data(repeating: 0, count: 32_000))
        }
        try await worker.endUtterance()
        return Double(output.frameLength) / 16_000 * Double(repetitions) + Double(repetitions)
    }
}

import CAudio
final class AudioProbeCounter: @unchecked Sendable {
    let pointer: OpaquePointer
    init() throws { guard let pointer = st_probe_create() else { throw AudioFailure.message("Cannot allocate probe counter") }; self.pointer = pointer }
    deinit { st_probe_destroy(pointer) }
}

extension AudioDiagnostics {
    /// Uses existing microphone authorization only. Counts buffers without reading, storing or recognizing samples.
    @MainActor public static func probeInputDevice(seconds: Double = 5) async throws -> String {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return "NOT_RUN microphone permission not already authorized" }
        let counter = try AudioProbeCounter()
        let engine = AVAudioEngine(); let input = engine.inputNode; let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format, block: AudioTapCallbacks.counting(counter: counter))
        defer { engine.stop(); input.removeTap(onBus: 0) }
        try engine.start(); try await Task.sleep(for: .seconds(min(10, max(1, seconds))))
        engine.stop()
        return "hardware_buffers=\(st_probe_buffers(counter.pointer)) hardware_frames=\(st_probe_frames(counter.pointer)) sample_rate=\(format.sampleRate) channels=\(format.channelCount) no_samples_read_saved_or_recognized=true"
    }
    /// A real-time producer feeding the same bounded C ring, AVAudioConverter, VAD and journal used by the mic.
    /// All samples originate in the explicitly provided synthetic file; no audio output or input device is opened.
    public static func exerciseRealtimeFixture(url: URL, seconds: Double, store: SaytileStore) async throws -> String {
        let file = try AVAudioFile(forReading: url)
        let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length))!
        try file.read(into: input)
        guard let samples = input.floatChannelData, input.format.channelCount == 1 else { throw AudioFailure.message("Real-time fixture must be mono Float32") }
        let ring = try AudioRing(capacity: UInt32(input.format.sampleRate * 4))
        let worker = try CaptureWorker(store: store, ring: ring, sampleRate: input.format.sampleRate, recognitionEnabled: false, update: { _, _ in }, failed: { message in print("CAPTURE_FAILURE \(message)") })
        await worker.start()
        let clock = ContinuousClock(); let start = clock.now
        let wanted = Int(seconds * input.format.sampleRate)
        let sampleCount = Int(input.frameLength)
        var produced = 0
        while produced < wanted {
            let index = produced % sampleCount
            let count = min(1_024, sampleCount - index, wanted - produced)
            var channel: UnsafeMutablePointer<Float>? = samples[0].advanced(by: index)
            withUnsafePointer(to: &channel) { st_ring_write(ring.pointer, $0, 1, UInt32(count)) }
            produced += count
            try await clock.sleep(until: start.advanced(by: .seconds(Double(produced) / input.format.sampleRate)))
        }
        await worker.stop()
        let records = try await store.listRecordings(limit: 1_000)
        let chunks = try await store.storageSummary()
        return "realtime_seconds=\(seconds) produced_frames=\(produced) dropped_frames=\(st_ring_dropped(ring.pointer)) records=\(records.count) saved_seconds=\(records.reduce(0) { $0 + $1.duration }) audio_bytes=\(chunks.audioBytes) all_available=\(records.allSatisfy { $0.audioState == .available }) all_finished=\(records.allSatisfy { !$0.isRecording }) pending_asr=\(chunks.pendingRecognitionCount)"
    }
}
