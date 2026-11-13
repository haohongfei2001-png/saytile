import CryptoKit
import Foundation
@testable import SaytileKit

/// Use the pinned public five-clip file. Check the bytes actually indexed in
/// SQLite and readable from WAVs after closing and reopening the data store.
@main struct MandarinRolloverProbe {
    struct Receipt: Encodable {
        let inputFrames: Int, storedFrames: Int
        let recordingFrames: [Int], chunks: Int
        let inputSHA256: String, storedSHA256: String
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let wave = try Data(contentsOf: url)
        precondition(digest(wave) == "5e7b5564803cec7cb90282b0427e99cd345472b758464060bf1f2ae5ba013c04")
        precondition(wave[36..<40] == Data("data".utf8) && wave.count == 44 + 620_800 * 2)
        let source = Data(wave.dropFirst(44))
        var rows = [Receipt]()
        for frames in [0, 17, 319, 320, 337, 640, 959, 960, 1280].map({ 481_280 + $0 }) + [620_800] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try SaytileStore(directory: root)
            let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 3200), sampleRate: 16_000,
                                           recognitionEnabled: false, update: { _, _ in }, failed: { _ in })
            let pcm = source.prefix(frames * 2)
            for start in stride(from: 0, to: pcm.count, by: 6400) {
                let end = min(pcm.count, start + 6400)
                try await worker.acceptPCM(pcm.subdata(in: start..<end),
                                           endingAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(end) / 32_000))
            }
            try await worker.flushTail()
            try await store.close()
            let restored = try SaytileStore(directory: root)
            var saved = Data(), counts = [Int](), chunks = 0
            for record in try await restored.listRecordings().reversed() {
                let before = saved.count
                for chunk in try await restored.audioChunks(recordingID: record.id) {
                    let audio = try Data(contentsOf: await restored.audioURL(for: chunk))
                    precondition(audio.count == 44 + Int(chunk.frames) * 2)
                    saved.append(audio.dropFirst(44))
                    chunks += 1
                }
                counts.append((saved.count - before) / 2)
            }
            try await restored.close()
            rows.append(Receipt(inputFrames: frames, storedFrames: saved.count / 2,
                                recordingFrames: counts, chunks: chunks,
                                inputSHA256: digest(pcm), storedSHA256: digest(saved)))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileHandle.standardOutput.write(contentsOf: encoder.encode(rows))
    }
}
