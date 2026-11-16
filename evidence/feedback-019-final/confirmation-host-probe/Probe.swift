import AppKit
import SwiftUI

@MainActor final class ProbeState: ObservableObject {
    @Published var showing = false
    var confirmations = 0
}
struct ProbeView: View {
    @ObservedObject var state: ProbeState
    var body: some View {
        Form {
            Section {
                Text("TEST_ONLY：隔离确认对话框")
                Button("撤回") { state.showing = true }
            }
            Section { Text("TEST_ONLY") }
                .confirmationDialog("撤回这条反馈？", isPresented: $state.showing) {
                    Button("撤回反馈", role: .destructive) { state.confirmations += 1; state.showing = false }
                } message: { Text("测试确认；不会调用网络或读取用户资料。") }
        }.formStyle(.grouped)
    }
}
@MainActor final class ProbePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@main struct Probe {
    @MainActor static func main() {
        let app = NSApplication.shared
        let mode = CommandLine.arguments[1]
        let initialPolicy = app.activationPolicy().rawValue
        let accepted = app.setActivationPolicy(.accessory)
        print("HOST policy=\(mode) accepted=\(accepted) initial=\(initialPolicy) actual=\(app.activationPolicy().rawValue)")
        let state = ProbeState()
        let panel = ProbePanel(contentRect: NSRect(x: 0,y: 0,width: 760,height: 820), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Saytile UI Review timeline-feedback-controls"
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: ProbeView(state: state).preferredColorScheme(.light))
        panel.setFrameOrigin(NSPoint(x: (NSScreen.screens.map { $0.frame.maxX }.max() ?? 0) + 64,y: 0))
        panel.orderFrontRegardless()
        let activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            if let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               running.processIdentifier == ProcessInfo.processInfo.processIdentifier { print("HOST_ACTIVATED_SELF") }
        }
        Task { @MainActor in
            if mode == "prohibited" {
                let result = app.setActivationPolicy(.prohibited)
                print("HOST_RUNNING_POLICY accepted=\(result) actual=\(app.activationPolicy().rawValue)")
            }
            defer { NSWorkspace.shared.notificationCenter.removeObserver(activation); panel.orderOut(nil) }
            @MainActor func snapshot(_ phase: String) {
                print("HOST_SNAPSHOT \(phase) self_frontmost=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier) confirming=\(state.showing) confirmations=\(state.confirmations)")
                for window in NSApp.windows { print("HOST_WINDOW \(String(describing:type(of:window))) visible=\(window.isVisible) key=\(window.isKeyWindow) canKey=\(window.canBecomeKey) style=\(window.styleMask.rawValue)") }
            }
            @MainActor func action(_ label: String, _ extra: [String] = []) async -> Int32 {
                let process = Process(), pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/private/tmp/saytile-feedback-confirmation-probe")
                process.arguments = [String(ProcessInfo.processInfo.processIdentifier),label,panel.title] + extra
                process.standardOutput=pipe; process.standardError=pipe
                do { try process.run() } catch { print("HELPER_LAUNCH_FAIL"); return 9 }
                let result = await Task.detached { let data=pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); return (process.terminationStatus,String(decoding:data,as:UTF8.self)) }.value
                print(result.1); return result.0
            }
            try? await Task.sleep(for:.milliseconds(500)); snapshot("before")
            let opened = await action("撤回")
            try? await Task.sleep(for:.milliseconds(300)); snapshot("opened")
            guard opened == 0, NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { print("HOST_FAIL_OPEN"); app.terminate(nil); return }
            let confirmed = await action("撤回反馈", ["feedback-confirmation","press"])
            try? await Task.sleep(for:.milliseconds(300)); snapshot("confirmed")
            print("HOST_RESULT confirmed=\(confirmed) count=\(state.confirmations) showing=\(state.showing)")
            app.terminate(nil)
        }
        app.run()
    }
}
