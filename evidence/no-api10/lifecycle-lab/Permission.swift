import AppKit
import AVFoundation
@testable import SaytileKit

@main struct PermissionState {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3, Bundle.main.bundleIdentifier == "app.saytile.hosted.freeze.permission" else { exit(64) }
        let directory = URL(fileURLWithPath: args[1])
        let store = try SaytileStore(directory: directory)
        let controller = AudioController(store: store, startupRecoveryReady: false)
        controller.selectDevice(uid: "app.saytile.intentionally.absent")
        let before = AVCaptureDevice.authorizationStatus(for: .audio)
        await controller.start(requestPermission: false)
        let after = AVCaptureDevice.authorizationStatus(for: .audio)
        let records = try await store.listRecordings(limit: 2).count
        let row: [String: Any] = ["before": before.rawValue, "after": after.rawValue, "running":controller.state.isRunning,
                                  "records":records,"permission_issue":controller.issue?.contains("权限") == true]
        await controller.shutdown();try await store.close()
        try JSONSerialization.data(withJSONObject:row).write(to:URL(fileURLWithPath:args[2]),options:.atomic)
    }
}
