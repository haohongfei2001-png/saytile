// Deterministic operating-system fault injection against the real coordinator and
// SQLite store. Does not read AX, activate a window, type, or access the clipboard.
import Foundation
@testable import SaytileKit

@MainActor
private final class WitnessFaultAccess: InputAccess {
    var hasPermission = true
    var target = InputTargetSnapshot(processID: 987654, applicationID: "test.witness", applicationName: "Synthetic witness",
        windowID: UUID(), elementID: UUID(), pageIdentity: "fixture://one", selectionLocation: 2,
        selectionLength: 0, isWeb: true, isEditable: true, isSensitive: false, canSetSelectedText: true)
    var field = "abz"
    var attempts = 0, readsAfterWrite = 0, completeAfterGap = 0, outerReads = 0
    var inject = false
    var ownNotification = false
    let scenario: String
    var onChange: (@MainActor (InputTargetChange) -> Void)?
    var cancel: (@MainActor () -> Void)?
    init(_ scenario: String) { self.scenario = scenario }
    func snapshot() throws -> InputTargetSnapshot {
        if inject && scenario == "safari-budget" && !ownNotification {
            outerReads += 1
            if outerReads == 1 {
                ownNotification = true; onChange?(.contentOrSelection); ownNotification = false
            }
            if outerReads == 2 || outerReads == 3 { throw NativeInputError.unsupported }
        }
        return target
    }
    func textWitness(at expected: InputTargetSnapshot) -> String? { try? checkedTextWitness(at: expected) }
    func checkedTextWitness(at expected: InputTargetSnapshot) throws -> String? {
        if inject {
            readsAfterWrite += 1
            if scenario != "safari-budget" && readsAfterWrite == 2 || scenario == "persistent" && readsAfterWrite > 2 ||
                scenario == "one-settled-read" && readsAfterWrite == 4 {
                throw NativeInputError.unsupported
            }
            if readsAfterWrite == 3 {
                switch scenario {
                case "changed-window": target.windowID = UUID()
                case "changed-editor": target.elementID = UUID()
                case "changed-page": target.pageIdentity = "fixture://other-page"
                case "changed-caret": target.selectionLocation -= 1
                case "selected-range": target.selectionLength = 1
                case "changed-prefix": field = "Ab你好😀z"
                case "changed-suffix": field = "ab你好😀Z"
                case "incomplete-page": target.pageContextComplete = false
                case "focus": onChange?(.focusOrDocument)
                case "content": onChange?(.contentOrSelection)
                case "layout": onChange?(.layout)
                case "cancel": cancel?()
                default: break
                }
            }
            if readsAfterWrite > 2 { completeAfterGap += 1 }
        }
        return expected == target ? field : nil
    }
    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? {
        guard expected == target else { return false }
        return RecognitionUTF16.slice(field, start: utf16Start, end: utf16Start + text.utf16.count)?.utf8.elementsEqual(text.utf8)
    }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport {
        self.onChange = onChange
        return .init(focus: true, content: true, page: true)
    }
    func stopObserving() { onChange = nil }
    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool {
        guard expected == target,
              let result = OwnedInputText.replacing(field, start: target.selectionLocation, expected: "", replacement: text) else { return false }
        attempts += 1; field = result; target.selectionLocation += text.utf16.count
        onChange?(.contentOrSelection)
        inject = true
        throw AXTextWriteTimeout()
    }
    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? {
        guard target.sameTarget(as: before), target.selectionLength == 0,
              target.selectionLocation == before.selectionLocation + text.utf16.count,
              matchesText(text, utf16Start: before.selectionLocation, at: target) == true else { return nil }
        return target
    }
}

@main
private enum InputWitnessSettlementProbe {
    @MainActor static func main() async throws {
        let scenarios = ["restored", "persistent", "one-settled-read", "changed-window", "changed-editor", "changed-page",
            "changed-caret", "selected-range", "changed-prefix", "changed-suffix", "incomplete-page", "focus", "content", "layout", "cancel", "safari-budget"]
        var results: [[String: Any]] = []
        for scenario in scenarios {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-witness-" + UUID().uuidString)
            let store = try SaytileStore(directory: directory), access = WitnessFaultAccess(scenario)
            let input = NativeInputCoordinator(store: store, access: access)
            access.cancel = { input.invalidate() }
            try await input.bindCurrentTarget()
            let recording = try await store.createRecording()
            let revision = try await store.saveEdit(recordingID: recording.id, text: "你好😀")
            let began = ProcessInfo.processInfo.systemUptime
            let result = await input.insertStable(recordingID: recording.id, revisionID: revision.id,
                stableUTF16End: revision.text.utf16.count, recordingStartedAt: recording.createdAt)
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            let expected: NativeInputResult = scenario == "restored" ? .confirmed : .unverified
            let bindingCorrect = (input.binding != nil) == (scenario == "restored")
            access.inject = false
            let repeatResult = await input.insertStable(recordingID: recording.id, revisionID: revision.id,
                stableUTF16End: revision.text.utf16.count, recordingStartedAt: recording.createdAt)
            let repeatCorrect = repeatResult == (scenario == "restored" ? .noNewText : .cancelled)
            let passed = result == expected && bindingCorrect && repeatCorrect && access.attempts == 1 &&
                access.readsAfterWrite >= 3 &&
                (scenario != "restored" || access.completeAfterGap >= 2)
            results.append(["scenario": scenario, "status": passed ? "PASS" : "FAIL", "actual": String(describing: result),
                "expected": String(describing: expected), "binding_correct": bindingCorrect,
                "repeat_suppressed": repeatCorrect, "write_attempts": access.attempts,
                "post_gap_challenge_exercised": access.readsAfterWrite >= 3,
                "witness_reads_after_write": access.readsAfterWrite, "complete_reads_after_gap": access.completeAfterGap,
                "outer_snapshot_reads": access.outerReads,
                "elapsed_seconds": elapsed])
            input.invalidate(); try await store.close()
            try FileManager.default.removeItem(at: directory)
        }
        let failures = results.filter { $0["status"] as? String == "FAIL" }.count
        let report: [String: Any] = ["scope": "production coordinator + SQLite; synthetic OS; no native AX or foreground use",
            "status": failures == 0 ? "PASS" : "FAIL", "scenarios": results.count, "passed": results.count - failures,
            "failed": failures, "results": results]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        exit(failures == 0 ? 0 : 1)
    }
}
