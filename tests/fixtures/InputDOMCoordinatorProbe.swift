import AppKit

// This test-only adapter bridges the real coordinator and SQLite ledger to a
// headless DOM fixture. It is not the macOS AX adapter or browser extension.
@MainActor
final class DOMInputAccess: InputAccess {
    let hasPermission = true
    var handler: (@MainActor (InputTargetChange) -> Void)?
    let windowID = UUID()
    var elementIDs: [String: UUID] = [:]
    func rpc(_ method: String, _ payload: [String: Any] = [:]) throws -> [String: Any] {
        var request = payload; request["method"] = method
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: request) + Data([10]))
        guard let response = readLine(), let data = response.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NativeInputError.unsupported }
        if let error = object["error"] as? String { throw ProbeFailure(message: error) }
        return object
    }
    func snapshot() throws -> InputTargetSnapshot {
        let response = try rpc("snapshot")
        let element = response["element"] as? String ?? "none"
        if elementIDs[element] == nil { elementIDs[element] = UUID() }
        return InputTargetSnapshot(processID: 12345, applicationID: "test.headless.dom", applicationName: "Synthetic DOM",
            windowID: windowID, elementID: elementIDs[element]!, pageIdentity: response["page"] as? String,
            selectionLocation: response["start"] as? Int ?? -1, selectionLength: response["length"] as? Int ?? 0,
            isWeb: true, isEditable: response["editable"] as? Bool ?? false, isSensitive: response["secure"] as? Bool ?? false,
            canSetSelectedText: true)
    }
    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool {
        guard try snapshot() == expected else { return false }
        return try rpc("dispatch", ["text": text])["ok"] as? Bool ?? false
    }
    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? {
        guard let current = try? snapshot(), current.sameTarget(as: before), current.selectionLength == 0,
              current.selectionLocation == before.selectionLocation + text.utf16.count,
              matchesText(text, utf16Start: before.selectionLocation, at: current) == true else { return nil }
        return current
    }
    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? {
        try? rpc("matches", ["text": text, "start": utf16Start])["ok"] as? Bool
    }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport {
        handler = onChange
        return .init(focus: true, content: true, page: true)
    }
    func stopObserving() { handler = nil }
    func mutation(_ name: String) throws {
        let response = try rpc("mutation", ["name": name])
        for change in response["changes"] as? [String] ?? [] {
            handler?(change == "layout" ? .layout : change == "focus" ? .focusOrDocument : .contentOrSelection)
        }
    }
}
struct ProbeFailure: Error { let message: String }
@main struct InputDOMCoordinatorProbe {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-dom-store-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let access = DOMInputAccess()
        let input = NativeInputCoordinator(store: store, access: access)
        var count = 0
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw ProbeFailure(message: message) }
            count += 1; _ = try access.rpc("pass", ["message": message])
        }
        for kind in ["textarea", "contenteditable"] {
            _ = try access.rpc("reset", ["kind": kind])
            let binding = try await input.bindCurrentTarget()
            let record = try await store.createRecording(createdAt: binding.boundAt.addingTimeInterval(1))
            let first = try await store.saveEdit(recordingID: record.id, text: "中文😀")
            let result = await input.insertStable(recordingID: record.id, revisionID: first.id, stableUTF16End: first.text.utf16.count, recordingStartedAt: record.createdAt)
            try expect(result == .confirmed, kind + " confirms UTF16 insertion through production coordinator")
            let repeated = await input.insertStable(recordingID: record.id, revisionID: first.id, stableUTF16End: first.text.utf16.count, recordingStartedAt: record.createdAt)
            try expect(repeated == .noNewText, kind + " suppresses duplicate stable range")
            let second = try await store.saveEdit(recordingID: record.id, text: "中文😀接着说")
            let suffix = await input.insertStable(recordingID: record.id, revisionID: second.id, stableUTF16End: second.text.utf16.count, recordingStartedAt: record.createdAt)
            let state = try access.rpc("state")
            try expect(suffix == .confirmed && state["text"] as? String == "PREFIX|中文😀接着说SUFFIX", kind + " appends only suffix and preserves surrounding text")
            try expect(state["sends"] as? Int == 0 && state["dispatches"] as? Int == 2, kind + " never sends or retries")
            try access.mutation("selection")
            try expect(input.binding == nil, kind + " selected text invalidates binding")
            let stopped = await input.insert(recordingID: record.id, revisionID: first.id)
            try expect(stopped == .cancelled, kind + " never replaces selected text")
            for mutation in ["sameURL", "replace", "newURL", "focusAwayBack"] {
                _ = try access.rpc("reset", ["kind": kind]); try await input.bindCurrentTarget()
                try access.mutation(mutation)
                try expect(input.binding == nil, kind + " rejects stale context after " + mutation)
            }
        }
        _ = try access.rpc("complete", ["checks": count, "scope": "Production Swift coordinator + SQLite + test-only DOM adapter; not native AX"])
    }
}
