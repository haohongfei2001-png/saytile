import AppKit
import ApplicationServices
@testable import SaytileKit

@MainActor
@main struct OwnedRangeNativeProbe {
    struct Failure: Error { let message: String }
    @MainActor final class SelectionChoice { var alternate = false }
    static let prefix = "用户前缀😀｜", suffix = "用户后缀🚀"
    static let original = "50😀", corrected = "500👩🏽‍💻", continuation = "，后续。"
    static func emit(_ line: String) { print(line); fflush(stdout) }
    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }
    static func blocked(_ message: String) -> Never { emit("BLOCKED " + message); exit(5) }
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.12)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func main() async {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard AXIsProcessTrusted() else { blocked("AX_PERMISSION_UNAVAILABLE_NO_PROMPT") }
        if CommandLine.arguments == [CommandLine.arguments[0], "--preflight"] {
            emit("PREFLIGHT_AX_TRUSTED_NO_PROMPT"); return
        }
        do { try await run() }
        catch let error as Failure { emit("FAIL " + error.message); exit(1) }
        catch { emit("FAIL production-or-probe-error \(String(describing: error))"); exit(1) }
    }
    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let pid = Int32(args[1]), pid > 1,
              UUID(uuidString: args[2]) != nil else {
            throw Failure(message: "invalid fixture identity arguments")
        }
        guard let application = NSRunningApplication(processIdentifier: pid) else {
            blocked("OWN_FIXTURE_REGISTRATION_UNAVAILABLE")
        }
        let nonce = args[2], scratch = URL(fileURLWithPath: args[3]).standardizedFileURL.resolvingSymlinksInPath()
        let executable = scratch.appendingPathComponent("OwnedRangeNativeTextFixture")
        try require(application.executableURL?.resolvingSymlinksInPath() == executable,
                    "fixture executable must be this run's exact binary")
        try require(scratch.lastPathComponent.hasPrefix("saytile-owned-range-native-"), "unique scratch required")
        let audit = FixtureActivationAudit(fixturePID: pid)
        defer { _ = audit.finish() }
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier != pid, "fixture must remain background")
        let root = AXUIElementCreateApplication(pid)
        guard let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement],
              let window = windows.first(where: { attribute($0, kAXTitleAttribute) as? String == "Saytile owned-range " + nonce }) else {
            blocked("OWN_FIXTURE_AX_WINDOW_UNAVAILABLE_NO_FOCUS_ESCALATION")
        }
        var queue = [window], fields: [String: AXUIElement] = [:], seen = Set<CFHashCode>()
        while !queue.isEmpty && seen.count < 64 {
            let node = queue.removeFirst()
            guard seen.insert(CFHash(node)).inserted else { continue }
            var owner: pid_t = 0
            try require(AXUIElementGetPid(node, &owner) == .success && owner == pid, "AX node PID mismatch")
            if attribute(node, kAXRoleAttribute) as? String == kAXTextAreaRole,
               let id = attribute(node, kAXIdentifierAttribute) as? String { fields[id] = node }
            queue += (attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        guard let primary = fields["owned-range-\(nonce)-0"], let alternate = fields["owned-range-\(nonce)-1"] else {
            blocked("OWN_FIXTURE_TEXT_AREAS_UNAVAILABLE")
        }
        let choice = SelectionChoice()
        let access = AXInputAccess(selectionProvider: {
            guard !application.isTerminated,
                  application.executableURL?.resolvingSymlinksInPath() == executable,
                  let currentWindows = attribute(root, kAXWindowsAttribute) as? [AXUIElement],
                  currentWindows.contains(where: { CFEqual($0, window) }) else { throw NativeInputError.targetChanged }
            let field = choice.alternate ? alternate : primary
            var owner: pid_t = 0, settable = DarwinBoolean(false)
            guard AXUIElementGetPid(field, &owner) == .success, owner == pid,
                  AXUIElementIsAttributeSettable(field, kAXSelectedTextAttribute as CFString, &settable) == .success,
                  settable.boolValue else { throw NativeInputError.unsupported }
            // Check capability on EVERY selection call so dispatch cannot use clipboard fallback.
            return AXInputSelection(application: application, root: root, window: window, element: field)
        })
        guard let snapshot = try? access.snapshot() else { blocked("OWN_FIXTURE_AX_SNAPSHOT_UNAVAILABLE") }
        var rangeSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(primary, kAXSelectedTextRangeAttribute as CFString, &rangeSettable) == .success,
              rangeSettable.boolValue, access.textWitness(at: snapshot) == prefix + suffix else {
            blocked("AX_RANGE_SETTER_OR_TEXT_WITNESS_UNAVAILABLE")
        }
        let support = access.observe(snapshot) { _ in }
        access.stopObserving()
        guard support.focus && support.content else { blocked("AX_OWNERSHIP_OBSERVATION_UNAVAILABLE") }
        let pasteboardGeneration = NSPasteboard.general.changeCount // Metadata only; never read clipboard content.

        func rpc(_ command: String) throws -> [String: Any] {
            emit("FIXTURE_RPC " + command)
            guard let line = readLine(), let data = line.data(using: .utf8),
                  let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  response["command"] as? String == command, response["nonce"] as? String == nonce,
                  response["pid"] as? Int32 == pid else { throw Failure(message: "fixture IPC identity mismatch") }
            return response
        }
        func state(_ response: [String: Any], _ key: String = "primary") throws -> [String: Any] {
            guard let result = response[key] as? [String: Any] else { throw Failure(message: "missing fixture state") }
            return result
        }
        func checkState(_ response: [String: Any], expected: String, texts: [String], ranges: Int) throws {
            let value = try state(response), other = try state(response, "alternate")
            try require((value["text"] as? String)?.utf8.elementsEqual(expected.utf8) == true, "fixture exact text mismatch")
            try require(other["text"] as? String == prefix + suffix, "alternate target modified")
            let attempts = value["textAttempts"] as? [[String: Any]] ?? []
            try require(attempts.compactMap { $0["text"] as? String } == texts, "selected-text attempts mismatch")
            try require((value["rangeAttempts"] as? [[String: Int]])?.count == ranges, "selected-range attempts mismatch")
            for (index, field) in [value, other].enumerated() {
                let full = field["fullValueAttempts"] as? Int ?? -1
                let keys = field["keyEvents"] as? Int ?? -1
                let pastes = field["pasteAttempts"] as? Int ?? -1
                let unexpected = field["unexpectedPayload"] as? Bool ?? true
                emit("AX_SAFETY_STATE field=\(index) full_value=\(full) key_events=\(keys) paste=\(pastes) unexpected_payload=\(unexpected)")
                try require(full == 0 && keys == 0 && pastes == 0 && !unexpected,
                    "forbidden full-value/key/paste/payload attempt")
            }
            try require((other["textAttempts"] as? [[String: Any]])?.isEmpty == true &&
                        (other["rangeAttempts"] as? [[String: Int]])?.isEmpty == true, "alternate target setter attempted")
            try require(NSPasteboard.general.changeCount == pasteboardGeneration, "clipboard generation changed; no cause inferred")
        }

        let scenarios = ["repair-and-continue", "shorter-repair-and-continue", "manual-edit", "selection-change",
                         "target-change", "setter-refusal", "focus-change", "restart-before-repair", "window-closed"]
        for scenario in scenarios {
            let original = scenario == "shorter-repair-and-continue" ? Self.corrected : Self.original
            let corrected = scenario == "shorter-repair-and-continue" ? Self.original : Self.corrected
            choice.alternate = false
            _ = try rpc("reset")
            // Flush notifications from the fixture's local setup before creating a new binding.
            try await Task.sleep(for: .milliseconds(100))
            let directory = scratch.appendingPathComponent("store-" + scenario)
            var store = try SaytileStore(directory: directory)
            var coordinator = NativeInputCoordinator(store: store, access: access)
            let binding = try await coordinator.bindCurrentTarget()
            let record = try await store.createRecording()
            let ticket = try await store.beginFusionRecognition(recordingID: record.id)
            var runs: [ModelRunTicket] = [], sequence: Int64 = 0
            for purpose in [RecognitionPurpose.chineseASR, .englishASR] {
                runs.append(try await store.beginModelRun(ticket: ticket, configuration: .init(purpose: purpose,
                    provider: purpose == .chineseASR ? .qwenMessage : .assemblyAI, model: "synthetic-native-owned-range")))
            }
            // Synthetic complete candidate evidence only. No providers, keys, audio, or network.
            func publish(_ text: String) async throws -> FusionPublication {
                sequence += 1
                let values = runs.map { RecognitionCandidate(run: $0, sequence: sequence, text: text,
                    stableUTF16Length: text.utf16.count, audioEndSeconds: 1, isComplete: true) }
                for value in values { try require(try await store.appendRecognitionCandidate(value), "candidate rejected") }
                let reserved = try await store.fusionReservedPrefix(recordingID: record.id)
                let proposal = try PrecisionFusion.validateSelection(spans: [.init(candidateID: values[0].id,
                    utf16Start: 0, utf16End: text.utf16.count)], candidates: values, committedPrefix: reserved, unresolved: false)
                return try await store.publishFusion(ticket: ticket, proposal: proposal)
            }
            guard let initial = try await publish(original).revision else { throw Failure(message: "initial publication missing") }
            try require(await coordinator.insertStable(recordingID: record.id, revisionID: initial.id,
                stableUTF16End: original.utf16.count, recordingStartedAt: record.createdAt) == .confirmed,
                "original real AX insertion not confirmed")
            let inserted = try rpc("state")
            try checkState(inserted, expected: prefix + original + suffix, texts: [original], ranges: 0)
            let insertionAttempts = try state(inserted)["textAttempts"] as! [[String: Any]]
            try require(insertionAttempts[0]["location"] as? Int == prefix.utf16.count &&
                        insertionAttempts[0]["length"] as? Int == 0, "initial insertion UTF16 range mismatch")
            _ = try await publish(corrected)
            guard let correction = try await store.ownedCorrectionCandidates(bindingID: binding.id).first else {
                throw Failure(message: "Store-approved correction missing")
            }
            var db = try StoreDatabase(url: directory.appendingPathComponent("Saytile.sqlite"))
            try require(try db.rows("SELECT valid FROM owned_input_ranges").first?["valid"] == "1", "real insertion did not establish ownership")
            if scenario == "manual-edit" { _ = try rpc("manual-edit") }
            if scenario == "selection-change" { _ = try rpc("select") }
            if scenario == "target-change" { choice.alternate = true }
            if scenario == "setter-refusal" { _ = try rpc("reject-replacement") }
            if scenario == "focus-change" {
                let response = try rpc("focus-alternate")
                try require(response["firstResponder"] as? String == "alternate" &&
                    response["firstResponderIdentifier"] as? String == "owned-range-\(nonce)-1" &&
                    attribute(alternate, kAXIdentifierAttribute) as? String == response["firstResponderIdentifier"] as? String,
                    "owned window first responder did not change to the verified AX element")
                // This background panel deliberately cannot take keyboard focus. Reflect
                // its real first responder in the injected target selector; do not claim
                // a foreground focus notification or fabricate a coordinator callback.
                choice.alternate = true
            }
            if scenario == "window-closed" { _ = try rpc("close-window") }
            if scenario == "restart-before-repair" {
                // Persist the exact pre-write state, reopen the real database, then
                // prove that a new coordinator cannot replay the uncertain operation.
                guard let operation = try await store.reserveOwnedCorrection(bindingID: binding.id,
                    revision: correction, targetStart: prefix.utf16.count, expectedText: original) else {
                    throw Failure(message: "restart reservation missing")
                }
                coordinator.invalidate(); try db.close(); try await store.close()
                store = try SaytileStore(directory: directory)
                db = try StoreDatabase(url: directory.appendingPathComponent("Saytile.sqlite"))
                coordinator = NativeInputCoordinator(store: store, access: access)
                try require(try await store.ownedCorrectionState(id: operation.id) == "unverified",
                            "restart must preserve uncertainty without replay")
                let newBinding = try await coordinator.bindCurrentTarget()
                try require(try await store.ownedCorrectionCandidates(bindingID: newBinding.id).isEmpty,
                            "new binding cannot recover old correction ownership")
            }
            if ["manual-edit", "selection-change", "focus-change", "window-closed"].contains(scenario) {
                try await Task.sleep(for: .milliseconds(100))
            }
            let result = await coordinator.repairOwned(revision: correction)
            let successful = scenario == "repair-and-continue" || scenario == "shorter-repair-and-continue"
            try require(result == (successful ? .confirmed : .correctionPending), "unexpected repair result: " + scenario)
            let attempted = successful || scenario == "setter-refusal"
            let expected = prefix + (successful ? corrected : scenario == "manual-edit" ? "99😀" : original) + suffix
            let texts = attempted ? [original, corrected] : [original]
            let repaired = try rpc("state")
            try checkState(repaired, expected: expected, texts: texts, ranges: attempted ? 1 : 0)
            if successful {
                let value = try state(repaired)
                try require(value["location"] as? Int == prefix.utf16.count + corrected.utf16.count &&
                            value["length"] as? Int == 0, "corrected UTF16 caret mismatch")
            }
            if attempted {
                let value = try state(repaired)
                let range = (value["rangeAttempts"] as! [[String: Int]])[0]
                let text = (value["textAttempts"] as! [[String: Any]])[1]
                try require(range["location"] == prefix.utf16.count && range["length"] == original.utf16.count &&
                    text["location"] as? Int == prefix.utf16.count && text["length"] as? Int == original.utf16.count,
                    "replacement must target only the exact UTF16 owned range")
            }
            // Deliberately re-enter the public API to prove its no-replay guard; no harness retry.
            let repeated = await coordinator.repairOwned(revision: correction)
            try require(repeated == (successful ? .noNewText : .correctionPending), "duplicate repair not refused")
            try checkState(try rpc("state"), expected: expected, texts: texts, ranges: attempted ? 1 : 0)
            if successful {
                try require(try db.rows("SELECT state FROM owned_corrections").map { $0["state"]! } == ["confirmed"], "correction journal not confirmed exactly once")
                try require(try await store.fusionReservedPrefix(recordingID: record.id) == corrected, "effective prefix not advanced")
                guard let next = try await publish(corrected + continuation).revision else { throw Failure(message: "continuation missing") }
                try require(await coordinator.insertStable(recordingID: record.id, revisionID: next.id,
                    stableUTF16End: next.text.utf16.count, recordingStartedAt: record.createdAt) == .confirmed, "continuation failed")
                try require(await coordinator.insertStable(recordingID: record.id, revisionID: next.id,
                    stableUTF16End: next.text.utf16.count, recordingStartedAt: record.createdAt) == .noNewText, "continuation duplicated")
                let final = try rpc("state")
                try checkState(final, expected: prefix + corrected + continuation + suffix,
                               texts: [original, corrected, continuation], ranges: 1)
                let value = try state(final), attempts = value["textAttempts"] as! [[String: Any]]
                try require(attempts[2]["location"] as? Int == prefix.utf16.count + corrected.utf16.count &&
                    attempts[2]["length"] as? Int == 0 && value["location"] as? Int == prefix.utf16.count + corrected.utf16.count + continuation.utf16.count &&
                    value["length"] as? Int == 0, "continuation UTF16 caret mismatch")
                let ops = try db.rows("SELECT text,start_utf16,end_utf16,state FROM dispatches ORDER BY rowid")
                try require(ops.count == 2 && ops.map { $0["text"]! } == [original, continuation] &&
                    ops.allSatisfy { $0["state"] == "confirmed" } && ops[0]["end_utf16"] == ops[1]["start_utf16"],
                    "append ledger must contain only original and new suffix")
            } else {
                let ops = try db.rows("SELECT state FROM owned_corrections")
                try require(ops.count <= 1 && ops.allSatisfy { ["pending", "unverified"].contains($0["state"] ?? "") }, "refusal journal cannot claim confirmation")
                if scenario == "setter-refusal" { try require(ops.first?["state"] == "unverified", "dropped setter must be unverified") }
                try require(try await store.revisions(recordingID: record.id).contains { $0.id == correction.id }, "refused correction archive lost")
            }
            coordinator.invalidate(); try db.close(); try await store.close()
            emit("PASS \(scenario) real_AX=true exact_fixture_PID=true text_attempts=\(successful ? 3 : texts.count) correction_range_attempts=\(attempted ? 1 : 0) no_replay=true")
        }
        let activation = audit.finish()
        try require(!activation.ownedActivated, "owned fixture or probe activated")
        emit("PASS safety no_full_value=true no_clipboard_change=true no_key_return_send=true no_owned_activation=true")
        emit("OWNED_RANGE_NATIVE_PASS scenarios=\(scenarios.count) target_selection_injected=true production_foreground_resolver=NOT_RUN")
    }
}
