import Foundation
@preconcurrency import AVFoundation

/// Offline fixture import used by acceptance tests. Never opens a microphone or external application.
public enum AudioDiagnostics {
    @discardableResult public static func transcribeFixture(url: URL, store: SaytileStore) async throws -> UUID {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else { throw AudioFailure.message("无法转换测试音频") }
        let record = try await store.createRecording()
        let journal = try PCMJournal(directory: store.audioDirectory, recordingID: record.id)
        try journal.openChunk()
        try await store.registerAudioChunk(recordingID: record.id, relativePath: journal.relativePath, frames: 0)
        let ticket = try await store.beginRecognition(recordingID: record.id)
        let session = LiveSpeechSession(store: store, ticket: ticket)
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
            try await Task.sleep(for: .milliseconds(30))
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
                for chunk in try await store.audioChunks(recordingID: record.id) {
                    let url = try await store.audioURL(for: chunk)
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        try await store.markAudioMissing(recordingID: record.id, message: "部分原音文件缺失，文字已保留")
                        break
                    }
                    do {
                        let frames = try PCMJournal.repair(url)
                        if frames != chunk.frames { try await store.reconcileAudioChunk(recordingID: record.id, path: chunk.relativePath, actualFrames: frames); count += 1 }
                    } catch {
                        try await store.markAudioMissing(recordingID: record.id, message: "原音文件不完整，文字已保留：\(error.localizedDescription)")
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
