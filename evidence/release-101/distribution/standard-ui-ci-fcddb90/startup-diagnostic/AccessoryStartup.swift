import AppKit
func checkpoint(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ note: Notification) { checkpoint("will_finish_launching") }
    func applicationDidFinishLaunching(_ note: Notification) {
        checkpoint("did_finish_launching")
        Task { @MainActor in
            checkpoint("main_actor_task")
            try? await Task.sleep(for: .milliseconds(50))
            checkpoint("main_actor_resumed active=\(NSApp.isActive)")
            exit(0)
        }
    }
}
@main struct Entry {
    @MainActor static func main() {
        checkpoint("main_entered")
        let app = NSApplication.shared
        checkpoint("shared_application")
        app.setActivationPolicy(.accessory)
        checkpoint("activation_accessory")
        let delegate = Delegate()
        app.delegate = delegate
        checkpoint("before_app_run active=\(app.isActive)")
        withExtendedLifetime(delegate) { app.run() }
    }
}
