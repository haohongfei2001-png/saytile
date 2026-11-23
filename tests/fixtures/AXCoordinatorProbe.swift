import AppKit
#if SAYTILE_PACKAGE_PROBE
@testable import SaytileKit
#endif
import ApplicationServices

// Link the production SaytileKit package. Inject only owned target selection
// and the explicitly counted deterministic post-dispatch target-side mutation.
@main
struct AXCoordinatorProbe {
    struct Failure: Error { let description: String }
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]),
              let app = NSRunningApplication(processIdentifier: pid) else { exit(2) }
        guard AXIsProcessTrusted() else { print("NO_ACCESSIBILITY_PERMISSION_NO_PROMPT"); exit(5) }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let activationAudit = FixtureActivationAudit(fixturePID: pid)
        guard frontmost != pid else { throw Failure(description: "Fixture unexpectedly owns foreground") }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
            return result
        }
        let root = AXUIElementCreateApplication(pid)
        let windows = (attribute(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        guard let window = windows.first else { throw Failure(description: "Fixture window unavailable") }
        var nodes = windows, textField: AXUIElement?
        while !nodes.isEmpty {
            let node = nodes.removeFirst()
            if attribute(node, kAXRoleAttribute) as? String == kAXTextAreaRole { textField = node; break }
            nodes += (attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        guard let field = textField else { throw Failure(description: "Fixture field unavailable") }
        guard attribute(field, kAXValueAttribute) as? String == "PREFIX|SUFFIX" else {
            throw Failure(description: "Fixture initial text changed; unexpected contents omitted")
        }
        let selector = { @MainActor in AXInputSelection(application: app, root: root, window: window, element: field) }
        let access = AXInputAccess(selectionProvider: selector)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-rc-input-store-" + UUID().uuidString)
        var completed = false
        defer {
            if completed { try? FileManager.default.removeItem(at: directory) }
            else { print("OWNED_TEST_STORE_RETAINED " + directory.path) }
        }
        let store = try SaytileStore(directory: directory)
        let coordinator = NativeInputCoordinator(store: store, access: access)
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
            checks += 1; print("PASS " + message); fflush(nil)
        }
        if let replay = ProcessInfo.processInfo.environment["SAYTILE_QWEN_PREVIEW_REPLAY"] {
            // Only a hash-recorded public fixture is supplied by the harness.
            // Replay recognition events, not keyboard events, against this PID.
            let data = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: replay))) as! [String: Any]
            let events = data["rawWorkerEvents"] as! [[String: Any]]
            let binding = try await coordinator.bindCurrentTarget()
            let recording = try await store.createRecording(createdAt: binding.boundAt.addingTimeInterval(1))
            let ticket = try await store.beginRecognition(recordingID: recording.id)
            let ingress = LocalCandidateIngress(store: store, ticket: ticket, model: .qwen)
            var preview = LocalLiveText(model: .qwen, previewPolicy: .provisional)
            var partials = 0, finalText = "", firstPreview: Double?
            for event in events {
                let kind = event["kind"] as! String, text = event["text"] as! String
                guard ["partial", "final"].contains(kind), !text.isEmpty else { continue }
                let final = kind == "final"
                guard let stable = preview.accept(text, final: final) else { continue }
                try await ingress.receive(.init(text: preview.presentation, stableUTF16Length: stable,
                    audioEndSeconds: Double(event["frames"] as! Int) / 16_000, isComplete: final))
                if !final {
                    if firstPreview == nil { firstPreview = event["t"] as? Double }
                    partials += 1
                    guard stable == 0, try await store.latestDispatchableRevision(recordingID: recording.id) == nil,
                          attribute(field, kAXValueAttribute) as? String == "PREFIX|SUFFIX" else {
                        throw Failure(description: "Unconfirmed Qwen preview gained external text ownership")
                    }
                } else {
                    finalText = text
                    try await ingress.finish()
                    guard let revision = try await store.latestDispatchableRevision(recordingID: recording.id) else {
                        throw Failure(description: "Qwen EOS has no dispatchable revision")
                    }
                    try expect(await coordinator.insertStable(recordingID: recording.id, revisionID: revision.id,
                        stableUTF16End: text.utf16.count, recordingStartedAt: recording.createdAt) == .confirmed,
                        "Qwen original EOS enters real AX target after preview-only updates")
                    try expect(attribute(field, kAXValueAttribute) as? String == "PREFIX|" + text + "SUFFIX",
                        "Qwen final preserves external prefix and suffix")
                    try expect(await coordinator.insertStable(recordingID: recording.id, revisionID: revision.id,
                        stableUTF16End: text.utf16.count, recordingStartedAt: recording.createdAt) == .noNewText,
                        "Qwen EOS replay does not duplicate text")
                    print("QWEN_INPUT_EXPERIENCE partials=\(partials) first_preview_original_t=\(firstPreview ?? -1) first_dispatchable_original_t=\(event["t"]!) replay_is_accelerated=true")
                    break // One complete actual recording, not concatenated archive history.
                }
            }
            try expect(partials >= 2 && !finalText.isEmpty, "real model generated multiple preview-only updates before EOS")
            coordinator.invalidate()
            // Restore only our exact inserted fixture span, without keyboard/focus.
            guard attribute(field, kAXValueAttribute) as? String == "PREFIX|" + finalText + "SUFFIX" else {
                throw Failure(description: "Owned fixture changed before cleanup")
            }
            var selected = CFRange(location: 7, length: finalText.utf16.count)
            guard let range = AXValueCreate(.cfRange, &selected),
                  AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, range) == .success,
                  AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, "" as CFString) == .success else {
                throw Failure(description: "Owned fixture cleanup failed")
            }
            try expect(!activationAudit.finish().ownedActivated, "Qwen external replay never acquires focus")
            try await store.close(); completed = true
            print("QWEN_NATIVE_INPUT_PASS \(checks); stable0_during_speech=true; live_foreground_resolver=NOT_RUN")
            return
        }
        let historical = try await store.createRecording(createdAt: .now.addingTimeInterval(-600))
        let historicText = try await store.saveEdit(recordingID: historical.id, text: "历史草稿不应出现在外部窗口")
        try await store.finishRecording(id: historical.id)
        let binding = try await coordinator.bindCurrentTarget()
        let recording = try await store.createRecording(createdAt: binding.boundAt.addingTimeInterval(1))
        let revision1 = try await store.saveEdit(recordingID: recording.id, text: "你好😀")
        let inserted = await coordinator.insertStable(recordingID: recording.id, revisionID: revision1.id, stableUTF16End: 4, recordingStartedAt: recording.createdAt)
        try expect(inserted == .confirmed, "production coordinator + SQLite reservation + real AX insertion confirms")
        try expect(attribute(field, kAXValueAttribute) as? String == "PREFIX|你好😀SUFFIX", "preserves synthetic prefix and suffix")
        let history = try await store.timelinePage(.ending(at: 1))
        let candidates = try await store.directInputCandidates(bindingID: binding.id, createdSince: binding.boundAt)
        let refused = await coordinator.insertStable(recordingID: historical.id, revisionID: historicText.id,
            stableUTF16End: historicText.text.utf16.count, recordingStartedAt: historical.createdAt)
        try expect(history.entries.first?.id == historical.id && !candidates.contains(where: { $0.id == historical.id }) &&
            refused == .noNewText && attribute(field, kAXValueAttribute) as? String == "PREFIX|你好😀SUFFIX",
            "history paging and explicit old-range replay leave owned external AX field untouched")
        let duplicate = await coordinator.insertStable(recordingID: recording.id, revisionID: revision1.id, stableUTF16End: 4, recordingStartedAt: recording.createdAt)
        try expect(duplicate == .noNewText, "same stable range is not inserted twice")
        let revision2 = try await store.saveEdit(recordingID: recording.id, text: "你好😀，接着说")
        let suffix = await coordinator.insertStable(recordingID: recording.id, revisionID: revision2.id, stableUTF16End: revision2.text.utf16.count, recordingStartedAt: recording.createdAt)
        try expect(suffix == .confirmed, "next stable suffix inserts after actual UTF16 caret")
        try expect(attribute(field, kAXValueAttribute) as? String == "PREFIX|你好😀，接着说SUFFIX", "no duplicate prefix or whole-field replacement")
        var selection = CFRange(location: 0, length: 6)
        let range = AXValueCreate(.cfRange, &selection)!
        guard AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, range) == .success else { throw Failure(description: "Fixture selection not settable") }
        try await Task.sleep(for: .milliseconds(100))
        try expect(coordinator.binding == nil, "real AX selection notification invalidates binding before next operation")
        let selectedResult = await coordinator.insert(recordingID: recording.id, revisionID: revision1.id)
        try expect(selectedResult != .confirmed && attribute(field, kAXValueAttribute) as? String == "PREFIX|你好😀，接着说SUFFIX", "real selected range prevents replacement")
        selection = CFRange(location: 7, length: 0)
        let caret = AXValueCreate(.cfRange, &selection)!
        _ = AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, caret)
        try await Task.sleep(for: .milliseconds(100))
        try await coordinator.bindCurrentTarget(purpose: .manual)
        let cancelled = Task { await coordinator.insert(recordingID: recording.id, revisionID: revision1.id) }
        cancelled.cancel()
        try expect(await cancelled.value == .cancelled, "cancelled production insertion has no external attempt")
        coordinator.invalidate()
        let activation = activationAudit.finish()
        print("NATIVE_AX_FOREGROUND_OBSERVATION unchanged=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost) owned_activated=\(activation.ownedActivated) outside_activation_events=\(activation.outsideActivations); no cause inferred for outside transitions")
        try expect(!activation.ownedActivated, "owned fixture and probe never activate")
        print("RC_AX_COORDINATOR_PASS \(checks) checks; background target selection injected; no production foreground or browser claim")

        // A deterministic independent target edit occurs AFTER the real production
        // setter and BEFORE its confirmation window. It is not a second Saytile attempt.
        let mutationAudit = FixtureActivationAudit(fixturePID: pid)
        let mutationAccess = TargetMutationAccess(base: AXInputAccess(selectionProvider: selector), field: field)
        let mutationCoordinator = NativeInputCoordinator(store: store, access: mutationAccess)
        let mutationBinding = try await mutationCoordinator.bindCurrentTarget()
        let mutationRecording = try await store.createRecording(createdAt: mutationBinding.boundAt.addingTimeInterval(1))
        let mutationRevision = try await store.saveEdit(recordingID: mutationRecording.id, text: "新句")
        let changed = await mutationCoordinator.insertStable(recordingID: mutationRecording.id, revisionID: mutationRevision.id,
            stableUTF16End: 2, recordingStartedAt: mutationRecording.createdAt)
        var mutationChecks = 0
        func requireMutation(_ condition: Bool, _ label: String) throws {
            guard condition else { throw Failure(description: label) }
            mutationChecks += 1; print("PASS " + label); fflush(nil)
        }
        try requireMutation(changed == .unverified && mutationCoordinator.binding == nil,
                            "post-setter external target change remains unverified and invalidates binding")
        let expectedAfterMutation = "PREFIX|新句 你好😀，接着说SUFFIX"
        try requireMutation(mutationAccess.productionDispatches == 1 && mutationAccess.externalMutations == 1 &&
                            attribute(field, kAXValueAttribute) as? String == expectedAfterMutation,
                            "one production AX insertion and one separately counted target edit preserve surrounding text")
        let db = try StoreDatabase(url: directory.appendingPathComponent("Saytile.sqlite"))
        let operations = try db.rows("SELECT state FROM dispatches WHERE recording_id=?", [.text(mutationRecording.id.uuidString)])
        let ownership = try db.rows("SELECT valid FROM owned_input_ranges WHERE recording_id=?", [.text(mutationRecording.id.uuidString)])
        try requireMutation(operations.count == 1 && operations.first?["state"] == "unverified" && ownership.isEmpty,
                            "uncertain insertion ledger is durable with no owned range")
        let repeated = await mutationCoordinator.insertStable(recordingID: mutationRecording.id, revisionID: mutationRevision.id,
            stableUTF16End: 2, recordingStartedAt: mutationRecording.createdAt)
        try requireMutation(repeated == .cancelled && mutationAccess.productionDispatches == 1 &&
                            mutationAccess.externalMutations == 1 && attribute(field, kAXValueAttribute) as? String == expectedAfterMutation,
                            "explicit repeat is refused without a second dispatch or target rewrite")
        try requireMutation(!mutationAudit.finish().ownedActivated, "external target-change scenario never activates an owned process")
        try db.close(); try await store.close(); completed = true
        print("TARGET_MUTATION_PASS \(mutationChecks) checks; production_dispatches=\(mutationAccess.productionDispatches) external_mutations=\(mutationAccess.externalMutations) no_replay=true")
    }
}

@MainActor
private final class TargetMutationAccess: InputAccess {
    let base: AXInputAccess
    let field: AXUIElement
    private(set) var productionDispatches = 0
    private(set) var externalMutations = 0
    init(base: AXInputAccess, field: AXUIElement) { self.base = base; self.field = field }
    var hasPermission: Bool { base.hasPermission }
    func snapshot() throws -> InputTargetSnapshot { try base.snapshot() }
    func dispatch(_ text: String, to expected: InputTargetSnapshot) throws -> Bool {
        productionDispatches += 1
        let result = try base.dispatch(text, to: expected)
        if result {
            externalMutations += 1
            guard AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, " " as CFString) == .success else {
                throw AXCoordinatorProbe.Failure(description: "Owned external mutation fixture could not edit its selected text")
            }
        }
        return result
    }
    func verify(_ text: String, at before: InputTargetSnapshot) -> InputTargetSnapshot? { base.verify(text, at: before) }
    func matchesText(_ text: String, utf16Start: Int, at expected: InputTargetSnapshot) -> Bool? { base.matchesText(text, utf16Start: utf16Start, at: expected) }
    func observe(_ expected: InputTargetSnapshot, onChange: @escaping @MainActor (InputTargetChange) -> Void) -> InputObservationSupport { base.observe(expected, onChange: onChange) }
    func stopObserving() { base.stopObserving() }
    func textWitness(at expected: InputTargetSnapshot) -> String? { base.textWitness(at: expected) }
}
