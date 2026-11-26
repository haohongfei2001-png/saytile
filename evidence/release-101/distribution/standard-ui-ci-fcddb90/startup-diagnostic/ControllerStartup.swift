import AppKit
import Sparkle
@MainActor final class AppModel {
var updateConfigured = false, canCheckForUpdates = false, automaticUpdateChecks = false
var expectsUpdateRelaunch = false
var updateStatus = "", updateActionTitle = ""
var checkForUpdates: (() -> Void)?
var setAutomaticUpdateChecks: (Bool) -> Void = { _ in }
}
func checkpoint(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
let model = AppModel()
var controller: AppUpdateController?
    func applicationWillFinishLaunching(_ note: Notification) { checkpoint("will_finish_launching") }
    func applicationDidFinishLaunching(_ note: Notification) {
        checkpoint("did_finish_launching")
        Task { @MainActor in
            checkpoint("main_actor_task")
            checkpoint("before_controller_init")
            controller = AppUpdateController(model: model, isolatedFixture: true)
            checkpoint("after_controller_init configured=\(model.updateConfigured) ready=\(model.canCheckForUpdates) status=\(model.updateStatus)")
            try? await Task.sleep(for: .milliseconds(50))
            checkpoint("main_actor_resumed")
            exit(0)
        }
    }
}
@main struct Entry {
    @MainActor static func main() {
        checkpoint("main_entered")
        let app = NSApplication.shared
        checkpoint("shared_application")
        app.setActivationPolicy(.prohibited)
        checkpoint("activation_prohibited")
        let delegate = Delegate()
        app.delegate = delegate
        checkpoint("before_app_run")
        withExtendedLifetime(delegate) { app.run() }
    }
}
