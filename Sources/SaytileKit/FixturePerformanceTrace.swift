import Foundation
import Synchronization

/// Bounded in-memory timing only for an explicitly requested disposable replay.
/// No audio, transcript, SQL, path or account value is recorded. Normal use has
/// no active recorder and never writes a trace. All timestamps use host uptime,
/// the same monotonic clock as the helper's decode events.
public enum FixturePerformanceTrace {
    public struct Event: Codable, Sendable {
        public let uptime: Double
        public let stage: String
        public let recordingID: UUID?
        public let frames: Int?
        public let duration: Double?
        public let decision: String?
    }
    public static let enabled = CommandLine.arguments.contains("--local-stream-probe")
        && CommandLine.arguments.contains("--performance-trace")
    private static let buffer = Mutex<[Event]>([])
    public static func record(_ stage: String, recordingID: UUID? = nil, frames: Int? = nil,
                              since: Double? = nil, decision: String? = nil) {
        guard enabled else { return }
        buffer.withLock { events in
            guard events.count < 50_000 else { return }
            // Timestamp and append share the lock: simultaneous producers must
            // not export an array whose clock order differs from event order.
            let now = ProcessInfo.processInfo.systemUptime
            events.append(Event(uptime: now, stage: stage, recordingID: recordingID, frames: frames,
                                duration: since.map { now - $0 }, decision: decision))
        }
    }
    public static var snapshot: [Event]? { enabled ? buffer.withLock { $0 } : nil }
}
