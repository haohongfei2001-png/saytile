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
        var targetWasFrontmost = false
        var otherTransitions = 0
        var previous = before
        let start = Date()
        while child.isRunning && Date().timeIntervalSince(start) < 8 {
            let current = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if current == child.processIdentifier { targetWasFrontmost = true }
            if current != previous {
                if current != child.processIdentifier { otherTransitions += 1 }
                previous = current
            }
            if current != before { changed = true }
            try await Task.sleep(for: .milliseconds(100))
        }
        if child.isRunning { child.terminate(); print("FAIL startup did not shut down"); exit(1) }
        let after = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print(output, terminator: "")
        print("FOCUS_ATTRIBUTION candidate_was_frontmost=\(targetWasFrontmost) other_application_transitions=\(otherTransitions); no identifiers or content logged")
        print("STARTUP_FOCUS_PROBE exit=\(child.terminationStatus) frontmost_unchanged=\(!changed && before == after) no_external_app_content_accessed=true")
        if child.terminationStatus != 0 || changed || before != after { exit(1) }
    }
}
