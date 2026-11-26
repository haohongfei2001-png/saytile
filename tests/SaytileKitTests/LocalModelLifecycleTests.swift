import Darwin
import Foundation
import Testing
@testable import SaytileKit

private enum LifecycleProbeError: Error { case timedOut }

private func waitForModelLifecycle(_ predicate: () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(8)
    while try await !predicate() {
        guard ContinuousClock.now < deadline else { throw LifecycleProbeError.timedOut }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Uses the actual ModelWorker pipe, session, capture journal and Store. Only the
/// model computation and asset validation are replaced; no microphone or model
/// download is involved. Each subprocess is owned by this isolated fixture.
private final class ModelLifecycleFixture: @unchecked Sendable {
    let root: URL
    let store: SaytileStore
    let service: LocalASRService
    let capture: CaptureWorker
    let pcm = Data(repeating: 0x21, count: 3_200)

    init(idleRetention: Duration = .seconds(30)) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "saytile-model-lease-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let worker = root.appending(path: "SaytileModelWorker")
        try Self.workerScript.write(to: worker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: worker.path)
        let directory = root
        service = LocalASRService(root: root.appending(path: "models"), helpers: root,
                                  idleRetention: idleRetention, validatedDirectory: { _ in directory })
        store = try SaytileStore(directory: root.appending(path: "data"))
        let factory = RecognitionSessionFactory()
        factory.selectLocal(live: .qwen, archive: .qwen, service: service)
        capture = try CaptureWorker(store: store, ring: AudioRing(capacity: 320), sampleRate: 16_000,
            recognitionFactory: factory, update: { _, _ in },
            failed: { Issue.record("Isolated model capture failed: \($0)") })
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    var launches: [Int32] {
        ((try? String(contentsOf: root.appending(path: "launches"), encoding: .utf8)) ?? "")
            .split(separator: "\n").compactMap { Int32($0) }
    }
    func alive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }
    func begin() async throws -> UUID {
        try await capture.beginUtterance()
        let id = try #require(await capture.recordingID)
        try await capture.append(pcm)
        try await waitForModelLifecycle { try await self.store.recording(id: id)?.text == "临时文字" }
        return id
    }
    func finish(_ id: UUID) async throws {
        try await capture.endUtterance()
        try await waitForModelLifecycle { try await self.store.recording(id: id)?.recognitionState == .completed }
        let record = try #require(try await store.recording(id: id))
        #expect(record.text == "完整文字" && record.audioState == .available)
        let chunk = try #require(try await store.audioChunks(recordingID: id).first)
        let audio = try Data(contentsOf: await store.audioURL(for: chunk))
        #expect(audio.dropFirst(44) == pcm)
    }
    func close() async throws {
        await capture.stop()
        await capture.cancelRecognitionAndWait()
        await service.releaseIdle()
        try await store.close()
    }

    private static let workerScript = #"""
    #!/usr/bin/env python3
    import json, os, pathlib, struct, sys
    root = pathlib.Path(sys.argv[2])
    with (root / "launches").open("a") as log:
        log.write(str(os.getpid()) + "\n")
    def publish(kind, text, frames):
        print(json.dumps(dict(kind=kind, text=text, frames=frames)), flush=True)
    def read(n):
        data = b""
        while len(data) < n:
            part = sys.stdin.buffer.read(n - len(data))
            if not part:
                raise EOFError()
            data += part
        return data
    publish("ready", "", 0)
    frames = 0
    while True:
        try:
            count, = struct.unpack("<I", read(4))
        except EOFError:
            break
        if count:
            frames += len(read(count)) // 2
            publish("partial", "临时文字", frames)
        else:
            publish("final", "完整文字" if frames else "", frames)
            frames = 0
    """#
}

@Suite("Local model warm retention and resource release")
struct LocalModelLifecycleTests {
    @Test func normalThinkingPauseReusesOneWorkerWithoutChangingSavedAudio() async throws {
        #expect(LocalASRService.warmIdleRetention == .seconds(180))
        let fixture = try ModelLifecycleFixture()
        do {
            let first = try await fixture.begin()
            try await fixture.finish(first)
            let pid = try #require(fixture.launches.first)
            try await Task.sleep(for: .milliseconds(100))
            #expect(fixture.alive(pid))
            #expect(try await fixture.store.listRecordings().count == 1)
            let second = try await fixture.begin()
            try await fixture.finish(second)
            #expect(fixture.launches == [pid])
            try await fixture.close()
        } catch { try? await fixture.close(); throw error }
    }

    enum ReleaseReason: CaseIterable { case paused, memoryPressure, explicit }
    @Test(arguments: ReleaseReason.allCases)
    func releaseDuringSpeechWaitsForItsFinalAndIsNotForgotten(reason: ReleaseReason) async throws {
        let fixture = try ModelLifecycleFixture()
        do {
            let first = try await fixture.begin()
            let pid = try #require(fixture.launches.first)
            switch reason {
            case .paused: await fixture.service.setStandbyEnabled(false)
            case .memoryPressure: await fixture.service.memoryPressureChanged(elevated: true)
            case .explicit: await fixture.service.releaseIdle()
            }
            #expect(fixture.alive(pid))
            try await fixture.finish(first)
            try await waitForModelLifecycle { !fixture.alive(pid) }
            await fixture.service.setStandbyEnabled(true)
            await fixture.service.memoryPressureChanged(elevated: false)
            let second = try await fixture.begin()
            try await fixture.finish(second)
            #expect(fixture.launches.count == 2)
            try await fixture.close()
        } catch { try? await fixture.close(); throw error }
    }

    @Test func expiredOldLeaseCannotInterruptNewSpeechAndLongIdleReleasesWorker() async throws {
        let fixture = try ModelLifecycleFixture(idleRetention: .seconds(2))
        do {
            let first = try await fixture.begin()
            try await fixture.finish(first)
            let second = try await fixture.begin()
            let activePID = try #require(fixture.launches.last)
            try await Task.sleep(for: .milliseconds(2_200))
            #expect(fixture.alive(activePID))
            try await fixture.finish(second)
            try await waitForModelLifecycle { !fixture.alive(activePID) }
            let before = fixture.launches.count
            let third = try await fixture.begin()
            try await fixture.finish(third)
            #expect(fixture.launches.count == before + 1)
            try await fixture.close()
        } catch { try? await fixture.close(); throw error }
    }

    @MainActor @Test func controllerPauseAndShutdownReleaseEvenWhenAlreadyPaused() async throws {
        let fixture = try ModelLifecycleFixture()
        let controller = AudioController(store: fixture.store)
        controller.selectLocalModels(live: .qwen, archive: .qwen, service: fixture.service)
        await controller.pause()
        do {
            await fixture.service.setStandbyEnabled(true)
            let first = try await fixture.begin()
            try await fixture.finish(first)
            let firstPID = try #require(fixture.launches.last)
            await controller.pause()
            try await waitForModelLifecycle { !fixture.alive(firstPID) }
            await fixture.service.setStandbyEnabled(true)
            let second = try await fixture.begin()
            try await fixture.finish(second)
            let secondPID = try #require(fixture.launches.last)
            await controller.shutdown()
            try await waitForModelLifecycle { !fixture.alive(secondPID) }
            try await fixture.close()
        } catch { await controller.shutdown(); try? await fixture.close(); throw error }
    }
}
