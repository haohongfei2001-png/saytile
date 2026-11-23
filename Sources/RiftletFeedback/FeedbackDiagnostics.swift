import Foundation

/// A bounded session ring, not a log scraper. Event ingestion has no disk,
/// network, actor mailbox or task creation. Export is an immutable allowlist.
public final class FeedbackDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [FeedbackEvent] = []
    private var dropped = 0
    public init() {}
    public func record(_ fact: FeedbackFact, count: Int = 1) {
        lock.lock(); defer { lock.unlock() }
        if events.count == 64 { events.removeFirst(); dropped = min(9999, dropped + 1) }
        events.append(FeedbackEvent(fact, count: count))
    }
    public func snapshot() -> FeedbackDiagnostic {
        lock.lock(); defer { lock.unlock() }
        return FeedbackDiagnostic(events: events, dropped: dropped)
    }
}
