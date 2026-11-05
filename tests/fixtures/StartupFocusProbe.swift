import AppKit
import Foundation

@main struct StartupFocusProbe {
    @MainActor static func main() async throws {
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        child.arguments = ["--data-directory", CommandLine.arguments[2], "--focus-probe"]
        let pipe = Pipe(); child.standardOutput = pipe; child.standardError = pipe
        try child.run()
        var changed = false
        let start = Date()
        while child.isRunning && Date().timeIntervalSince(start) < 8 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != before { changed = true }
            try await Task.sleep(for: .milliseconds(100))
        }
        if child.isRunning { child.terminate(); print("FAIL startup did not shut down"); exit(1) }
        let after = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print(output, terminator: "")
        print("STARTUP_FOCUS_PROBE exit=\(child.terminationStatus) frontmost_unchanged=\(!changed && before == after) no_external_app_content_accessed=true")
        if child.terminationStatus != 0 || changed || before != after { exit(1) }
    }
}
