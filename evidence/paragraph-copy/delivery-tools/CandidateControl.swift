import AppKit
import Foundation
@main struct CandidateControl {
    @MainActor static func main() async throws {
        let id = "app.saytile.mac.mandarin-candidate"
        let path = URL(fileURLWithPath: "/Users/hhf/Applications/Saytile 中文识别候选.app").standardizedFileURL.path
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.bundleURL?.standardizedFileURL.path == path }
        switch CommandLine.arguments.dropFirst().first {
        case "stop":
            for app in matches {
                if !app.terminate() { throw CocoaError(.userCancelled) }
            }
            for _ in 0..<80 {
                if matches.allSatisfy(\.isTerminated) { print("old_instances=\(matches.count) graceful=true"); return }
                try await Task.sleep(for: .milliseconds(250))
            }
            throw CocoaError(.userCancelled)
        case "verify":
            for _ in 0..<60 {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.bundleURL?.standardizedFileURL.path == path && $0.isFinishedLaunching && !$0.isTerminated }) { print("candidate_pid=\(app.processIdentifier) launched=true"); return }
                try await Task.sleep(for: .milliseconds(250))
            }
            throw CocoaError(.executableNotLoadable)
        default: throw CocoaError(.featureUnsupported)
        }
    }
}
