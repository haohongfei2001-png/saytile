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
            let html = "<title>\(title)</title><textarea autofocus>PREFIX|SUFFIX</textarea>"
            try html.write(to: doc, atomically: true, encoding: .utf8)
            config.arguments = ["--user-data-dir=" + work.appendingPathComponent("profile").path,
                                "--no-first-run", "--no-default-browser-check", "--disable-sync",
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
        guard AXUIElementSetAttributeValue(target.element,kAXSelectedTextRangeAttribute as CFString,v)==AXError.success else { throw TargetError.unsupported("caret") }
        let access=AXInputAccess(selectionProvider:select)
        guard try access.snapshot().canSetSelectedText else { throw TargetError.unsupported("selected-text setter") }
        let store=try SaytileStore(directory:work.appendingPathComponent("store"))
        let coordinator=NativeInputCoordinator(store:store,access:access)
        try await waitForOwnedField(access, original: original, caret: 7, pid: pid)
        try await coordinator.bindCurrentTarget()
        let row=try await store.createRecording()
        let r=try await store.saveEdit(recordingID:row.id,text:"你好😀")
        func insert(_ rev:TranscriptRevision) async -> NativeInputResult {
            await coordinator.insertStable(recordingID:row.id,revisionID:rev.id,stableUTF16End:rev.text.utf16.count,recordingStartedAt:row.createdAt)
        }
        func matches(_ text:String) throws -> Bool { attribute(try select().element,kAXValueAttribute) as? String==text }
        let first=await insert(r)
        print("first",first,"target_match",try matches("PREFIX|你好😀SUFFIX"))
        guard first == .confirmed,try matches("PREFIX|你好😀SUFFIX") else { throw TargetError.mismatch("first insertion") }
        guard await insert(r) == .noNewText else { throw TargetError.mismatch("duplicate") }
        let next=try await store.saveEdit(recordingID:row.id,text:"你好😀，接着说")
        guard await insert(next) == .confirmed,try matches("PREFIX|你好😀，接着说SUFFIX") else { throw TargetError.mismatch("suffix") }
        // Edit the selection in the synthetic document while the previous binding is still live.
        range = CFRange(location:0,length:6)
        let selection=AXValueCreate(.cfRange,&range)!
        guard AXUIElementSetAttributeValue(try select().element,kAXSelectedTextRangeAttribute as CFString,selection) == .success else { throw TargetError.unsupported("change selection") }
        let changed=try await store.saveEdit(recordingID:row.id,text:"你好😀，接着说。")
        let stale=await insert(changed)
        guard stale != .confirmed && stale != .unverified,try matches("PREFIX|你好😀，接着说SUFFIX") else { throw TargetError.mismatch("target mutation") }
        coordinator.invalidate();try await store.close()
        print(browser ? "PASS_CHROME" : "PASS_TEXTEDIT", "foreground selected by WindowServer; Unicode insertion, prefix/suffix, deduplication, append and target mutation confirmed")
    }
}
