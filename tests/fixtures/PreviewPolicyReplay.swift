import Foundation
@testable import SaytileKit

/// Replays identical, previously captured model hypotheses. No inference or timing claims.
@main struct PreviewPolicyReplay {
    static func main() throws {
        let paths = CommandLine.arguments.dropFirst()
        var results: [[String: Any]] = []
        for path in paths {
            let input = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
            var strict = LocalLiveText(model: .qwen)
            var provisional = LocalLiveText(model: .qwen, previewPolicy: .provisional)
            var strictEvents: [[String: Any]] = [], previewEvents: [[String: Any]] = []
            for event in input["rawWorkerEvents"] as! [[String: Any]] {
                guard let text = event["text"] as? String, !text.isEmpty,
                      let kind = event["kind"] as? String, ["partial", "final"].contains(kind) else { continue }
                if let stable = strict.accept(text, final: kind == "final") {
                    strictEvents.append(["t": event["t"]!, "text": strict.presentation, "stable": stable, "kind": kind])
                }
                if let stable = provisional.accept(text, final: kind == "final") {
                    previewEvents.append(["t": event["t"]!, "text": provisional.presentation, "stable": stable, "kind": kind])
                }
            }
            results.append(["input": path, "confirmed": strictEvents, "provisional": previewEvents])
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]))
    }
}
