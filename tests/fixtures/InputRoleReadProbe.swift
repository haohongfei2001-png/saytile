// Real coordinator + SQLite, deterministic AX metadata fault injection. No AX,
// browser, keyboard, clipboard, foreground activation, or production data access.
import Foundation
import ApplicationServices
@testable import SaytileKit

@MainActor private final class RoleFaultAccess: InputAccess {
    var hasPermission = true
    var target = InputTargetSnapshot(processID: 987654, applicationID: "test.role", applicationName: "Synthetic role",
        windowID: UUID(), elementID: UUID(), pageIdentity: "fixture://one", selectionLocation: 2,
        selectionLength: 0, isWeb: true, isEditable: true, isSensitive: false, canSetSelectedText: true)
    var field = "abz"
    var writes = 0, postWriteReads = 0, fullWitnesses = 0, unknownReads = 0
    var deniedBeforeWriteReturn = false
    var onChange: (@MainActor (InputTargetChange) -> Void)?
    var afterNotification: (@MainActor () -> Void)?
    var bindingExists: (@MainActor () -> Bool)?
    let scenario: String
    let contextMode: Bool
    init(_ scenario: String, contextMode: Bool = false) { self.scenario = scenario; self.contextMode = contextMode }
    func snapshot() throws -> InputTargetSnapshot {
        guard writes > 0 else { return target }
        postWriteReads += 1
        if postWriteReads == 1 || scenario.hasPrefix("persistent-") ||
            scenario == "one-full-read" && postWriteReads > 2 {
            if contextMode {
                var transport = AXError.cannotComplete
                let error = AXValueCreate(.axError, &transport)!
                let items: [AnyObject]? = switch scenario {
                case "empty-restored": [kAXGroupRole as NSString]
                case "missing-restored": nil
                case "item-restored": [error, NSNull()]
                case "semantic-role-missing": [NSNull(), NSNull()]
                case "extra-batch": [kAXGroupRole as NSString, NSNull(), NSNull()]
                default: [kAXGroupRole as NSString, NSNull()]
                }
                let status: AXError = ["empty-restored", "missing-restored", "item-restored", "semantic-role-missing", "extra-batch"].contains(scenario) ? .success :
                    scenario == "invalid-element" ? .invalidUIElement : .cannotComplete
                var snapshot = target
                do {
                    let values = try AXInputAccess.contextAttributes(status: status, items: items, names: [kAXRoleAttribute, kAXTitleAttribute])
                    snapshot.pageContextComplete = values?[kAXRoleAttribute] as? String != nil
                } catch NativeInputError.unsupported {
                    let knownDenial = scenario.hasPrefix("known-")
                    if !knownDenial { unknownReads += 1 }
                    throw InputSafetyPolicy.contextReadFailure(editable: scenario != "known-disabled",
                        selectionLength: scenario == "known-selection" ? 1 : 0,
                        identityChanged: ["known-window", "known-editor", "known-process"].contains(scenario))
                }
                return snapshot
            }
            let role: String? = scenario == "empty-restored" ? "" :
                scenario == "readonly-restored" ? "AXStaticText" :
                scenario == "disabled-restored" ? "AXTextArea" : nil
            let enabled = !scenario.hasPrefix("disabled")
            var snapshot = target
            do { snapshot.isEditable = try InputSafetyPolicy.isEditable(role: role, enabled: enabled) }
            catch { unknownReads += 1; throw error }
            return snapshot
        }
        return target
    }
    func checkedTextWitness(at expected: InputTargetSnapshot) throws -> String? {
        guard expected == target else { return nil }
        if writes > 0 { fullWitnesses += 1 }
        return field
    }
    func textWitness(at expected: InputTargetSnapshot) -> String? { try? checkedTextWitness(at: expected) }
    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? {
        guard target == expected else { return false }
        return RecognitionUTF16.slice(field, start: utf16Start, end: utf16Start + text.utf16.count) == text
    }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport {
        self.onChange = onChange
        return .init(focus: true, content: true, page: true)
    }
    func stopObserving() { onChange = nil }
    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool {
        guard target == expected,
              let updated = OwnedInputText.replacing(field, start: target.selectionLocation, expected: "", replacement: text) else { return false }
        writes += 1; field = updated; target.selectionLocation += text.utf16.count
        onChange?(.contentOrSelection)
        deniedBeforeWriteReturn = bindingExists?() == false
        afterNotification?()
        return true
    }
    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? {
        guard let current = try? snapshot(), current.sameTarget(as: before), current.selectionLength == 0,
              current.selectionLocation == before.selectionLocation + text.utf16.count,
              matchesText(text, utf16Start: before.selectionLocation, at: current) == true else { return nil }
        return current
    }
}

@main private enum InputRoleReadProbe {
    @MainActor static func main() async throws {
        let contextMode = CommandLine.arguments.contains("--page-context")
        let initial = contextMode ? ["nil-restored", "empty-restored", "missing-restored", "item-restored",
            "semantic-role-missing", "invalid-element", "extra-batch", "known-disabled", "known-selection",
            "known-window", "known-editor", "known-process", "persistent-context"] :
            ["nil-restored", "empty-restored", "disabled-restored", "readonly-restored", "disabled-missing-role", "persistent-role"]
        let scenarios = initial + ["one-full-read", "second-content", "focus", "layout", "cancel", "changed-process",
            "changed-window", "changed-editor", "changed-page", "incomplete-page", "changed-caret", "selected-range",
            "changed-prefix", "changed-suffix", "sensitive"]
        var results: [[String: Any]] = []
        for scenario in scenarios {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-role-" + UUID().uuidString)
            let store = try SaytileStore(directory: directory), access = RoleFaultAccess(scenario, contextMode: contextMode)
            let input = NativeInputCoordinator(store: store, access: access)
            access.bindingExists = { input.binding != nil }
            access.afterNotification = {
                switch scenario {
                case "second-content": access.onChange?(.contentOrSelection)
                case "focus": access.onChange?(.focusOrDocument)
                case "layout": access.onChange?(.layout)
                case "cancel": input.invalidate()
                case "changed-process": access.target.processID += 1
                case "changed-window": access.target.windowID = UUID()
                case "changed-editor": access.target.elementID = UUID()
                case "changed-page": access.target.pageIdentity = "fixture://other"
                case "incomplete-page": access.target.pageContextComplete = false
                case "changed-caret": access.target.selectionLocation -= 1
                case "selected-range": access.target.selectionLength = 1
                case "changed-prefix": access.field = "Ab你好😀z"
                case "changed-suffix": access.field = "ab你好😀Z"
                case "sensitive": access.target.isSensitive = true
                default: break
                }
            }
            try await input.bindCurrentTarget()
            let recording = try await store.createRecording()
            let revision = try await store.saveEdit(recordingID: recording.id, text: "你好😀")
            let began = ProcessInfo.processInfo.systemUptime
            let result = await input.insertStable(recordingID: recording.id, revisionID: revision.id,
                stableUTF16End: revision.text.utf16.count, recordingStartedAt: recording.createdAt)
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            let recover = ["nil-restored", "empty-restored", "missing-restored", "item-restored"].contains(scenario)
            let explicitDenial = ["disabled-restored", "readonly-restored", "disabled-missing-role",
                "semantic-role-missing", "invalid-element", "extra-batch", "known-disabled", "known-selection",
                "known-window", "known-editor", "known-process"].contains(scenario)
            let repeatResult = await input.insertStable(recordingID: recording.id, revisionID: revision.id,
                stableUTF16End: revision.text.utf16.count, recordingStartedAt: recording.createdAt)
            let db = try StoreDatabase(url: directory.appendingPathComponent("Saytile.sqlite"), readOnly: true)
            let ownership = try db.rows("SELECT expected_text,valid FROM owned_input_ranges WHERE recording_id=?", [.text(recording.id.uuidString)])
            let ownershipCorrect = recover ? ownership.count == 1 && ownership.first?["expected_text"] == "你好😀" && ownership.first?["valid"] == "1" : ownership.isEmpty
            try db.close()
            let passed = result == (recover ? .confirmed : .unverified) &&
                repeatResult == (recover ? .noNewText : .cancelled) && (input.binding != nil) == recover && access.writes == 1 &&
                ownershipCorrect && (recover ? access.fullWitnesses >= 3 && access.unknownReads == 1 : true) &&
                (!explicitDenial || access.deniedBeforeWriteReturn && access.unknownReads == 0)
            results.append(["scenario": scenario, "status": passed ? "PASS" : "FAIL", "result": String(describing: result),
                "repeat_result": String(describing: repeatResult), "write_attempts": access.writes,
                "full_witnesses": access.fullWitnesses, contextMode ? "unknown_context_reads" : "unknown_role_reads": access.unknownReads,
                "explicit_denial_before_dispatch_return": access.deniedBeforeWriteReturn,
                "ownership_correct": ownershipCorrect, "elapsed_seconds": elapsed])
            input.invalidate(); try await store.close()
            try FileManager.default.removeItem(at: directory)
        }
        let failed = results.filter { $0["status"] as? String == "FAIL" }.count
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["status": failed == 0 ? "PASS" : "FAIL",
            "scope": "production AX metadata classification/coordinator/SQLite; simulated OS, native foreground NOT_RUN",
            "page_context_mode": contextMode,
            "scenarios": results.count, "passed": results.count - failed, "failed": failed, "results": results],
            options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        exit(failed == 0 ? 0 : 1)
    }
}
