import Foundation
@main struct Replay {
    static func main() throws {
        var result: [String: Any] = [:]
        for path in CommandLine.arguments.dropFirst() {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let input = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            var old = Baseline563(model: .qwen)
            var local = BoundedPreview(rejectReturns: false), protected = BoundedPreview(rejectReturns: true)
            var accumulated = "", events: [String: [[String: Any]]] = ["baseline": [], "local": [], "protected": []]
            for e in input["rawWorkerEvents"] as! [[String: Any]] {
                let kind = e["kind"] as! String, raw = e["text"] as! String
                guard kind != "ready", !raw.isEmpty else { continue }
                let final = kind == "final"
                let values = [("baseline", old.accept(raw, final: final), old.presentation),
                              ("local", local.accept(raw, final: final), local.presentation),
                              ("protected", protected.accept(raw, final: final), protected.presentation)]
                for (name, stable, text) in values {
                    if let stable {
                        precondition(final || stable == 0)
                        precondition(text == raw || (name == "baseline" && raw == text + "。"))
                        events[name]!.append(["t": e["t"]!, "text": accumulated + text, "kind": kind, "stable": stable])
                    }
                }
                if final {
                    accumulated += raw
                    old = Baseline563(model: .qwen)
                    local = BoundedPreview(rejectReturns: false); protected = BoundedPreview(rejectReturns: true)
                }
            }
            result[path] = events
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
