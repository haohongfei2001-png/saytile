import Foundation
import Testing
@testable import SaytileKit

private final class OwnershipGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    func open() { lock.withLock { opened = true } }
    func wait() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !lock.withLock({ opened }) && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
private final class OwnershipSession: RecognitionSession, @unchecked Sendable {
    let recordingID = UUID()
    private let lock = NSLock()
    private var cancellations = 0
    let release: OwnershipGate?
    init(release: OwnershipGate? = nil) { self.release = release }
    var cancelCount: Int { lock.withLock { cancellations } }
    var isComplete: Bool { cancelCount > 0 }
    func append(_ data: Data) {}
    func finish() {}
    func cancel() { lock.withLock { cancellations += 1 } }
    func wait() async { await release?.wait() }
}
private extension CaptureWorker {
    func installLifecycleFixture(session: any RecognitionSession, run: Task<Void, Never>?) {
        speech = session; runTask = run
    }
    func appendRetiredFixture(_ session: any RecognitionSession) { retired.append(session) }
}

@Suite("Capture session ownership across suspension")
struct CaptureOwnershipTests {
    @MainActor @Test func revocationCancelsAlreadyAdmittedSessionWhileCaptureStopIsSuspended() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-stop-owner-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 32_000), sampleRate: 16_000,
                                       recognitionEnabled: false, update: { _, _ in }, failed: { _ in })
        let releaseStop = OwnershipGate(), session = OwnershipSession()
        defer { releaseStop.open() }
        await worker.installLifecycleFixture(session: session, run: Task { await releaseStop.wait() })
        let controller = AudioController(store: store, initialWorker: worker)
        let stopping = Task { await controller.pause() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await !worker.stopping && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        #expect(await worker.stopping)
        await controller.setRecognitionConfiguration(RecognitionConfiguration())
        #expect(session.cancelCount == 1)
        releaseStop.open(); await stopping.value
        await controller.shutdown(); try await store.close()
    }

    @Test func cancellationOnlyRemovesCapturedSessionsNotNewlyRetiredOnes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-retired-owner-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 32_000), sampleRate: 16_000,
                                       recognitionEnabled: false, update: { _, _ in }, failed: { _ in })
        let releaseOld = OwnershipGate(), old = OwnershipSession(release: nil), next = OwnershipSession()
        let held = OwnershipSession(release: releaseOld)
        defer { releaseOld.open() }
        await worker.appendRetiredFixture(held)
        await worker.appendRetiredFixture(old)
        let cancelling = Task { await worker.cancelRecognitionAndWait() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while held.cancelCount == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        #expect(held.cancelCount == 1)
        await worker.appendRetiredFixture(next)
        releaseOld.open(); await cancelling.value
        #expect(await worker.retired.contains { $0 === next })
        await worker.cancelRecognitionAndWait()
        #expect(next.cancelCount == 1)
        #expect(old.cancelCount == 1)
        try await store.close()
    }
}
