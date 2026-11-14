// Current runner of the original frozen no-api.9 TextEdit scenarios.
import AppKit
import ApplicationServices
@testable import SaytileKit

enum TargetError: Error { case wrongDocument, unsupported(String), mismatch(String) }
func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(node,key as CFString,&result) == .success else { return nil }
    return result
}
/// TextEdit can expose a usable editor and filename before LaunchServices
/// assigns AXDocument. Both must identify the fixture before the first binding.
func matchesTextEditDocument(_ identity: String?, expected: URL) -> Bool {
    // Native AXInputAccess snapshots carry AXDocument and AXTitle in this order.
    guard let identity, let separator = identity.firstIndex(of: "\u{1f}") else { return false }
    let path = String(identity[..<separator])
    let title = identity[identity.index(after: separator)...]
    let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(string: path)
    guard !path.isEmpty, let url, url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
          url.resolvingSymlinksInPath().standardizedFileURL.path ==
            expected.resolvingSymlinksInPath().standardizedFileURL.path else { return false }
    return title == expected.lastPathComponent || title == expected.deletingPathExtension().lastPathComponent
}

@main struct HostedTextEdit {
    @MainActor static func main() async {
        do { try await test() }
        catch { print("CASE_INCOMPLETE",error); exit(2) }
    }
    @MainActor static func test() async throws {
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              ProcessInfo.processInfo.environment["SAYTILE_HOSTED_TARGETS"] == "1",
              AXIsProcessTrusted() else { throw TargetError.unsupported("dedicated trusted host required") }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let work=FileManager.default.temporaryDirectory.appendingPathComponent("saytile-textedit-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:false)
        let browser = CommandLine.arguments.contains("--chrome")
        let doc = work.appendingPathComponent("Saytile-owned-" + UUID().uuidString + (browser ? ".html" : ".txt"))
        let original = "PREFIX|SUFFIX"
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = true
        config.promptsUserIfNeeded = false
        setbuf(stdout, nil)
        let app: NSRunningApplication
        if browser {
            let title = doc.deletingPathExtension().lastPathComponent
            let html = """
                <!doctype html><meta charset="utf-8"><title>\(title)</title><h1>Saytile isolated document</h1>
                <form><label for="entry">Draft</label><textarea id="entry" autofocus>PREFIX|SUFFIX</textarea>
                <label for="other">Other draft</label><textarea id="other">OTHER</textarea><button>Send fixture only</button></form>
                <script>
                window.returnCount = 0; window.submitCount = 0;
                document.addEventListener('keydown', e => { if (e.key === 'Enter') { window.returnCount++; e.preventDefault(); } });
                document.querySelector('form').addEventListener('submit', e => { window.submitCount++; e.preventDefault(); });
                const draft = document.querySelector('#entry');
                window.sawFirst = false; window.sawAppendAfterFirst = false;
                draft.addEventListener('input', () => {
                    if (draft.value === 'PREFIX|你好😀SUFFIX') window.sawFirst = true;
                    if (window.sawFirst && draft.value === 'PREFIX|你好😀，接着说SUFFIX') window.sawAppendAfterFirst = true;
                });
                function start() { draft.setSelectionRange(7,7); }
                if (document.activeElement === draft) start(); else draft.addEventListener('focus', start, {once:true});
                </script>
                """
            try html.write(to: doc, atomically: true, encoding: .utf8)
            config.arguments = ["--user-data-dir=" + work.appendingPathComponent("profile").path,
                                "--remote-debugging-address=127.0.0.1", "--remote-debugging-port=0",
                                "--no-first-run", "--no-default-browser-check", "--disable-sync", "--disable-background-networking",
                                "--force-renderer-accessibility", "--app=" + doc.absoluteString]
            // LaunchServices can wait forever for Chrome's open-application
            // acknowledgement with an app-mode URL. Track the exact launched PID.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
            process.arguments = config.arguments + ["--disable-search-engine-choice-screen"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            print("Launched disposable Chrome process")
            var owned: NSRunningApplication?
            for _ in 0..<120 {
                if let running = NSRunningApplication(processIdentifier: process.processIdentifier),
                   running.isFinishedLaunching { owned = running; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard let owned else {
                if process.isRunning { process.terminate() }
                throw TargetError.unsupported("Chrome did not finish launching")
            }
            app = owned
            _ = app.activate()
            print("Owned browser process ready")
        } else {
            try original.write(to: doc, atomically: true, encoding: .utf8)
            app = try await NSWorkspace.shared.open([doc], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), configuration: config)
        }
        defer { app.forceTerminate() } // dedicated new process and synthetic document only
        let pid=app.processIdentifier
        func select() throws -> AXInputSelection {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier==pid else { throw TargetError.wrongDocument }
            let s=try AXInputAccess.frontmostSelection()
            guard s.application.processIdentifier==pid else { throw TargetError.wrongDocument }
            let path=attribute(s.window,kAXDocumentAttribute) as? String ?? ""
            let title=attribute(s.window,kAXTitleAttribute) as? String ?? ""
            guard path.contains(doc.lastPathComponent) || title.contains(doc.deletingPathExtension().lastPathComponent) else { throw TargetError.wrongDocument }
            return s
        }
        var ready:AXInputSelection?
        for _ in 0..<100 {
            if let s=try? select(), attribute(s.element,kAXRoleAttribute) as? String==kAXTextAreaRole as String { ready=s; break }
            try await Task.sleep(for:.milliseconds(100))
        }
        guard let target=ready else {
            let root=AXUIElementCreateApplication(pid)
            print("owned_pid_foreground",NSWorkspace.shared.frontmostApplication?.processIdentifier==pid,"has_focused_window",attribute(root,kAXFocusedWindowAttribute) != nil,"has_focused_editor",attribute(root,kAXFocusedUIElementAttribute) != nil)
            throw TargetError.unsupported("TextEdit did not expose owned focused window/editor")
        }
        guard attribute(target.element,kAXValueAttribute) as? String == original else { throw TargetError.mismatch("new document content") }
        var range=CFRange(location:7,length:0)
        let v=AXValueCreate(.cfRange,&range)!
        if !browser, AXUIElementSetAttributeValue(target.element,kAXSelectedTextRangeAttribute as CFString,v) != .success { throw TargetError.unsupported("caret") }
        let access=AXInputAccess(selectionProvider:select)
        // bindOwnedField requires the setter on every one of its complete samples.
        // The initial role/value can arrive before the focused AX range does.
        let store=try SaytileStore(directory:work.appendingPathComponent("store"))
        let trace = FixtureAccessTrace(access)
        let coordinator = NativeInputCoordinator(store: store, access: trace)
        coordinator.onBindingInvalidated = { print("OWNED_BINDING_INVALIDATED", trace.stage) }
        func dom(_ action: String, _ expected: String) throws -> [String: Any] {
            // Even if AX loses its focused editor, the read-only observation can
            // still report the exact state of the unique file in our new profile.
            // State-changing fixture actions also require the live AX selection.
            if action != "state" { _ = try select() }
            let tool = Process(), output = Pipe()
            tool.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            tool.arguments = ["node", "tests/fixtures/owned-chrome-draft.mjs", work.appendingPathComponent("profile/DevToolsActivePort").path,
                              doc.absoluteString, action, expected]
            tool.standardOutput = output
            try tool.run(); tool.waitUntilExit()
            let bytes = output.fileHandleForReading.readDataToEndOfFile()
            guard tool.terminationStatus == 0, let state = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  state["otherIntact"] as? Bool == true, state["enter"] as? Int == 0, state["submits"] as? Int == 0 else {
                throw TargetError.mismatch("independent DOM / zero sends")
            }
            return state
        }
        func checkDOM(_ text: String, caret: Int, otherFocused: Bool = false) throws {
            guard browser else { return }
            let state = try dom("state", text)
            print("OWNED_DOM", trace.stage, "exact", state["exact"] ?? false, "caret", state["start"] ?? -1,
                  "end", state["end"] ?? -1, "otherFocused", state["otherFocused"] ?? false, "enter=0 submits=0")
            if trace.stage == "append" {
                guard state["sawFirst"] as? Bool == true, state["sawAppendAfterFirst"] as? Bool == true else {
                    throw TargetError.mismatch("DOM did not observe both ordered insertions")
                }
            }
            guard state["exact"] as? Bool == true, state["start"] as? Int == caret, state["end"] as? Int == caret,
                  state["focused"] as? Bool == !otherFocused, state["otherFocused"] as? Bool == otherFocused else {
                throw TargetError.mismatch("independent DOM " + trace.stage)
            }
        }
        do {
            try await bindOwnedField(coordinator, trace: trace, original: original, caret: 7, pid: pid, expectingWeb: browser) { snapshot in
                browser || matchesTextEditDocument(snapshot.pageIdentity, expected: doc)
            }
        } catch {
            if let current = try? access.snapshot() {
                print("Owned field context complete", current.pageContextComplete, "has identity", current.pageIdentity != nil,
                      "known caret", current.selectionLocation == 7, "witness matches", access.textWitness(at: current) == original)
            } else {
                print("Owned field failure context unavailable")
            }
            throw error
        }
        let row=try await store.createRecording()
        let r=try await store.saveEdit(recordingID:row.id,text:"你好😀")
        func insert(_ rev:TranscriptRevision) async -> NativeInputResult {
            await coordinator.insertStable(recordingID:row.id,revisionID:rev.id,stableUTF16End:rev.text.utf16.count,recordingStartedAt:row.createdAt)
        }
        func matches(_ text:String) throws -> Bool { attribute(try select().element,kAXValueAttribute) as? String==text }
        let firstField = "PREFIX|你好😀SUFFIX", finalField = "PREFIX|你好😀，接着说SUFFIX"
        try checkDOM(original, caret: 7)
        trace.stage = "first"
        let first = await insert(r), firstMatches = try matches(firstField)
        print("OWNED_RESULT", trace.stage, first, "AX_exact", firstMatches, "writes", trace.writes)
        // Keep duplicate + suffix back-to-back. The page records both actual input events.
        guard first == .confirmed, firstMatches, trace.writes == 1 else { throw TargetError.mismatch("first insertion") }
        trace.stage = "duplicate"
        guard await insert(r) == .noNewText, trace.writes == 1 else { throw TargetError.mismatch("duplicate") }
        let next = try await store.saveEdit(recordingID: row.id, text: "你好😀，接着说")
        trace.stage = "append"
        let suffix = await insert(next)
        print("OWNED_RESULT", trace.stage, suffix, "writes", trace.writes)
        try checkDOM(finalField, caret: 15)
        let suffixMatches = try matches(finalField)
        print("OWNED_READBACK", trace.stage, "AX_exact", suffixMatches)
        guard suffix == .confirmed, suffixMatches, trace.writes == 2 else { throw TargetError.mismatch("suffix") }
        // Edit the selection in the synthetic document while the previous binding is still live.
        trace.stage = "changed-selection"
        range = CFRange(location:0,length:6)
        let selection=AXValueCreate(.cfRange,&range)!
        guard AXUIElementSetAttributeValue(try select().element,kAXSelectedTextRangeAttribute as CFString,selection) == .success else { throw TargetError.unsupported("change selection") }
        let changed=try await store.saveEdit(recordingID:row.id,text:"你好😀，接着说。")
        let stale=await insert(changed)
        guard stale != .confirmed && stale != .unverified, trace.writes == 2, try matches(finalField) else { throw TargetError.mismatch("target mutation") }
        if browser {
            let selected = try dom("state", finalField)
            guard selected["exact"] as? Bool == true, selected["start"] as? Int == 0, selected["end"] as? Int == 6 else {
                throw TargetError.mismatch("protected selection")
            }
            print("OWNED_PROTECTED_SELECTION", "range=0...6", "writes", trace.writes)
            // New scenario, same focused synthetic field. No reactivation or retry of a delivery.
            trace.stage = "before-manual-edit-bind"
            coordinator.invalidate()
            _ = try dom("collapse", finalField)
            try await bindOwnedField(coordinator, trace: trace, original: finalField, caret: 15, pid: pid, expectingWeb: browser)
            let record = try await store.createRecording()
            func send(_ text: String) async throws -> NativeInputResult {
                let revision = try await store.saveEdit(recordingID: record.id, text: text)
                return await coordinator.insertStable(recordingID: record.id, revisionID: revision.id,
                    stableUTF16End: text.utf16.count, recordingStartedAt: record.createdAt)
            }
            trace.stage = "before-manual-edit"
            let extraField = "PREFIX|你好😀，接着说好SUFFIX", edited = "EDITED|你好😀，接着说好SUFFIX"
            guard try await send("好") == .confirmed, trace.writes == 3 else { throw TargetError.mismatch(trace.stage) }
            try checkDOM(extraField, caret: 16)
            trace.stage = "manual-edit"
            _ = try dom("manualEdit", extraField)
            let rejected = try await send("好呀")
            guard rejected != .confirmed, rejected != .unverified, trace.writes == 3 else { throw TargetError.mismatch(trace.stage) }
            try checkDOM(edited, caret: 16)
            for scenario in ["cancel", "switch-target"] {
                trace.stage = scenario + "-bind"
                coordinator.invalidate()
                try await bindOwnedField(coordinator, trace: trace, original: edited, caret: 16, pid: pid, expectingWeb: browser)
                let fresh = try await store.createRecording()
                let revision = try await store.saveEdit(recordingID: fresh.id, text: "停")
                trace.stage = scenario
                if scenario == "cancel" { coordinator.invalidate() } else { _ = try dom("switchTarget", edited) }
                let result = await coordinator.insertStable(recordingID: fresh.id, revisionID: revision.id,
                    stableUTF16End: revision.text.utf16.count, recordingStartedAt: fresh.createdAt)
                guard result != .confirmed, result != .unverified, trace.writes == 3, coordinator.binding == nil else {
                    throw TargetError.mismatch(scenario)
                }
                try checkDOM(edited, caret: 16, otherFocused: scenario == "switch-target")
            }
        }
        coordinator.invalidate();try await store.close()
        print(browser ? "PASS_CHROME" : "PASS_TEXTEDIT", "foreground selected by WindowServer; Unicode insertion, prefix/suffix, deduplication, append and target mutation confirmed")
    }
}
