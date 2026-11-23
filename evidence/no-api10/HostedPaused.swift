import AppKit
import AVFoundation
import Darwin
@testable import SaytileKit

@main struct HostedPaused {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let store = try SaytileStore(directory: root.appendingPathComponent("store"))
        let controller = AudioController(store: store, startupRecoveryReady: false)
        await controller.pause()
        let center = NSWorkspace.shared.notificationCenter
        let file = root.appendingPathComponent("power-events.jsonl")
        let record: @MainActor @Sendable (String) -> Void = { name in
            func kernel(_ key: String) -> Double {
                var stamp = timeval(), size = MemoryLayout<timeval>.size
                guard sysctlbyname(key, &stamp, &size, nil, 0) == 0 else { return -1 }
                return Double(stamp.tv_sec) + Double(stamp.tv_usec) / 1_000_000
            }
            let row: [String: Any] = ["event": name, "unix": Date().timeIntervalSince1970,
                "paused": controller.state == .paused, "running": controller.state.isRunning,
                "kernelSleep": kernel("kern.sleeptime"), "kernelWake": kernel("kern.waketime"),
                "microphoneAuthorization": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
                "inputDeviceCount": controller.devices.count]
            guard let data = try? JSONSerialization.data(withJSONObject: row) else { return }
            if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
            guard let h = try? FileHandle(forWritingTo: file) else { return }; defer { try? h.close() }
            _ = try? h.seekToEnd(); try? h.write(contentsOf: data + Data([10])); try? h.synchronize()
        }
        let will = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in record("willSleep") }
        }
        let did = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                record("didWakeSettled")
            }
        }
        record("armed")
        // Parent signals completion with a private file after checking the real kernel pair.
        for _ in 0..<180 where !FileManager.default.fileExists(atPath: root.appendingPathComponent("done").path) {
            try await Task.sleep(for: .milliseconds(500))
        }
        record("finished"); center.removeObserver(will); center.removeObserver(did)
        await controller.shutdown(); try await store.close()
    }
}
