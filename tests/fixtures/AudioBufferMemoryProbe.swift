import Foundation
import Darwin
#if SAYTILE_PACKAGE_PROBE
@testable import SaytileKit
#endif

/// Accelerated production VoiceSegmenter resource regression, not a wall-clock soak.
@main struct AudioBufferMemoryProbe {
    static func main() throws {
        let segmenter = try VoiceSegmenter()
        let input = Data(repeating: 42, count: 1_334)
        // Warm the same Foundation/VAD code before measuring incremental retention.
        for _ in 0..<100 { _ = segmenter.accept(input) }
        var before = rusage(), after = rusage()
        guard getrusage(RUSAGE_SELF, &before) == 0 else { fatalError("getrusage failed") }
        var delivered = 0
        for _ in 0..<50_000 {
            for event in segmenter.accept(input) {
                switch event {
                case .audio(let data): delivered += data.count
                case .begin(let frames): delivered += frames.reduce(0) { $0 + $1.count }
                case .end: break
                }
            }
        }
        guard getrusage(RUSAGE_SELF, &after) == 0 else { fatalError("getrusage failed") }
        let growth = max(0, after.ru_maxrss - before.ru_maxrss)
        let result: [String: Any] = [
            "scope": "Accelerated real VoiceSegmenter; synthetic PCM; no microphone, ASR or wall-clock claim",
            "iterations": 50_000, "input_bytes": 66_700_000, "vad_emitted_bytes": delivered,
            "peak_rss_before_bytes": before.ru_maxrss, "peak_rss_after_bytes": after.ru_maxrss,
            "peak_rss_growth_bytes": growth, "allowed_growth_bytes": 8 * 1_024 * 1_024,
            "status": growth < 8 * 1_024 * 1_024 ? "PASS" : "FAIL"
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        if growth >= 8 * 1_024 * 1_024 { exit(1) }
    }
}
