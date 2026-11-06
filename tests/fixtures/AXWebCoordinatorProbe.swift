import AppKit
import ApplicationServices

@main
struct AXWebCoordinatorProbe {
    struct Failure: Error { let message: String }
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]), let app = NSRunningApplication(processIdentifier: pid) else { exit(2) }
        guard AXIsProcessTrusted() else { print("NO_ACCESSIBILITY_PERMISSION_NO_PROMPT"); exit(5) }
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard foreground != pid else { throw Failure(message: "Fixture owns foreground") }
        let root = AXUIElementCreateApplication(pid)
        func get(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var output: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &output) == .success else { return nil }
            return output
        }
        let windows = (get(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        guard let window = windows.first else { throw Failure(message: "No fixture window") }
        func findEditor() throws -> AXUIElement {
            var queue = windows, count = 0
            while !queue.isEmpty, count < 200 {
                count += 1; let node = queue.removeFirst()
                let role = get(node, kAXRoleAttribute) as? String ?? "unknown"
                if role == kAXTextAreaRole || role == kAXTextFieldRole { return node }
                queue += (get(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            }
            throw Failure(message: "No fixture web editor")
        }
        let access = AXInputAccess(selectionProvider: { AXInputSelection(application: app, root: root, window: window, element: try findEditor()) })
        let snapshot = try access.snapshot()
        let support = access.observe(snapshot) { _ in }
        print("WEB_AX_CAPABILITY isWeb=\(snapshot.isWeb) pageIdentity=\(snapshot.pageIdentity != nil) focus=\(support.focus) content=\(support.content) page=\(support.page) contextComplete=\(snapshot.pageContextComplete) selectedTextSettable=\(snapshot.canSetSelectedText) caret=\(snapshot.selectionLocation) localRange=\(String(describing: access.matchesText("", utf16Start: snapshot.selectionLocation, at: snapshot)))")
        access.stopObserving(); fflush(nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-rc-web-store-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SaytileStore(directory: directory)
        let coordinator = NativeInputCoordinator(store: store, access: access)
        var continuousAvailable = true
        do { try await coordinator.bindCurrentTarget() } catch {
            continuousAvailable = false; print("WEB_CONTINUOUS_REJECTED \(error.localizedDescription)")
            try await coordinator.bindCurrentTarget(purpose: .manual)
        }
        let record = try await store.createRecording(createdAt: Date().addingTimeInterval(1))
        let revision = try await store.saveEdit(recordingID: record.id, text: "网页😀")
        let result = continuousAvailable ? await coordinator.insertStable(recordingID: record.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count, recordingStartedAt: record.createdAt) : await coordinator.insert(recordingID: record.id, revisionID: revision.id)
        print("WEB_INSERT_RESULT \(result)"); fflush(nil)
        let actualText = get(try findEditor(), kAXValueAttribute) as? String
        print("WEB_ACTUAL_TEXT \(String(describing: actualText))"); fflush(nil)
        // A background-only WKWebView may acknowledge AXSelectedText without changing
        // its DOM value. Preserve the failed-attempt evidence; never activate it or resend.
        if actualText == "PREFIX|网页😀SUFFIX", result == .confirmed {
            print("PASS background WKWebView insertion confirmed")
        } else {
            guard result == .unverified else { throw Failure(message: "Unchanged web field falsely confirmed") }
            print("LIMIT background WKWebView AX setter acknowledged but value unchanged; marked unverified once")
        }
        coordinator.invalidate()
        // Test real WebKit AX notifications separately from the write precondition.
        var observerChecks = 0
        for mutation in ["sameURL", "silentContext", "replaceContext", "newURL", "replaceEditor", "select"] {
            print("FIXTURE_COMMAND restore"); fflush(nil)
            try await Task.sleep(for: .milliseconds(350))
            try await coordinator.bindCurrentTarget(purpose: .continuous)
            try await Task.sleep(for: .milliseconds(250))
            guard coordinator.binding != nil else { throw Failure(message: "Binding expired before isolated mutation " + mutation) }
            print("FIXTURE_COMMAND " + mutation); fflush(nil)
            for _ in 0..<30 where coordinator.binding != nil { try await Task.sleep(for: .milliseconds(50)) }
            if coordinator.binding == nil {
                observerChecks += 1
                print("PASS real WKWebView AX invalidates binding after " + mutation)
            } else {
                let beforeAttempt = get(try findEditor(), kAXValueAttribute) as? String
                let staleAttempt = await coordinator.insert(recordingID: record.id, revisionID: revision.id)
                let afterAttempt = get(try findEditor(), kAXValueAttribute) as? String
                if coordinator.binding == nil, staleAttempt != .confirmed, staleAttempt != .unverified, beforeAttempt == afterAttempt {
                    observerChecks += 1
                    print("PASS final semantic revalidation rejects " + mutation + " before dispatch despite missing AX event")
                } else {
                    print("FAIL real WKWebView retained unsafe binding after " + mutation)
                    coordinator.invalidate()
                }
            }
            fflush(nil)
        }
        for limitation in ["largeTree", "blankContext"] {
            print("FIXTURE_COMMAND restore"); fflush(nil)
            try await Task.sleep(for: .milliseconds(350))
            print("FIXTURE_COMMAND " + limitation); fflush(nil)
            try await Task.sleep(for: .milliseconds(350))
            let limited = try access.snapshot()
            guard !limited.pageContextComplete else { throw Failure(message: "Unsafe page reported complete context: " + limitation) }
            do {
                try await coordinator.bindCurrentTarget()
                throw Failure(message: "Unsafe automatic binding accepted: " + limitation)
            } catch NativeInputError.unobservablePage {
                print("PASS automatic binding rejects " + limitation + "; explicit manual binding remains available")
            }
            try await coordinator.bindCurrentTarget(purpose: .manual)
            coordinator.invalidate()
        }
        print("FIXTURE_COMMAND state"); fflush(nil)
        try await Task.sleep(for: .milliseconds(100))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground else { throw Failure(message: "Foreground changed") }
        print("WEB_AX_PROBE_COMPLETE observerChecks=\(observerChecks)/6 continuousAvailable=\(continuousAvailable); invisible isolated WKWebView, injected selection only, no foreground insertion claim")
        if observerChecks != 6 { exit(1) }
    }
}
