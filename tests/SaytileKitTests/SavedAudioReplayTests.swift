import Foundation
import Testing
@testable import SaytileKit

private final class ReplayConsumer: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed = 0.0
    private var received = 0
    private var maximumQueued = 0
    func append(_ data: Data) {
        lock.withLock {
            received += data.count
            maximumQueued = max(maximumQueued, received - Int((elapsed * 32_000).rounded()))
        }
    }
    func consume(seconds: Double) { lock.withLock { elapsed += seconds } }
    var result: (received: Int, elapsed: Double, maximumQueued: Int) {
        lock.withLock { (received, elapsed, maximumQueued) }
    }
}

@Suite("Saved audio real-time replay")
struct SavedAudioReplayTests {
    private func fixture(bytes: Int) throws -> (URL, FileHandle) {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-replay-" + UUID().uuidString)
        // Header contents are irrelevant to this PCM feed loop; only owned bytes are used.
        try (Data(repeating: 0, count: 44) + Data(repeating: 1, count: bytes)).write(to: path)
        return (path, try FileHandle(forReadingFrom: path))
    }
    @Test func fiveMinuteRecordingDoesNotOverrunHealthyRealtimeConsumer() async throws {
        let bytes = 300 * 32_000
        let (path, handle) = try fixture(bytes: bytes)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: path) }
        let consumer = ReplayConsumer()
        try await SavedAudioReplay.feed(handle: handle, append: consumer.append) { consumer.consume(seconds: $0) }
        let result = consumer.result
        #expect(result.received == bytes)
        #expect(abs(result.elapsed - 300) < 0.000_001)
        // The production fanout holds 300 chunks. One source block ahead is enough;
        // growing past that bound would reject a healthy 1x provider on long audio.
        #expect(result.maximumQueued <= 6_400)
        #expect(result.maximumQueued < 300 * 6_400)
    }
    @Test func shortFinalBlockUsesItsOwnDurationAndCancellationStopsBeforeNextBlock() async throws {
        let (path, handle) = try fixture(bytes: 6_400 + 1_234)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: path) }
        let consumer = ReplayConsumer()
        try await SavedAudioReplay.feed(handle: handle, append: consumer.append) { consumer.consume(seconds: $0) }
        #expect(consumer.result.received == 7_634)
        #expect(abs(consumer.result.elapsed - Double(7_634) / 32_000) < 0.000_001)

        let cancelled = ReplayConsumer()
        await #expect(throws: CancellationError.self) {
            try await SavedAudioReplay.feed(handle: handle, append: cancelled.append) { _ in throw CancellationError() }
        }
        #expect(cancelled.result.received == 6_400)
    }
}
