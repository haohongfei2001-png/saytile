import AppKit
@testable import SaytileVoiceUI

/// Replays only public fixture publications into the production AppKit surface.
/// A mouse-inert, nonactivating diagnostic window cannot acquire the user's input.
struct SurfaceRow: VoiceTranscriptEntry {
    let id: UUID
    let position: Int64 = 1
    var displayText: String
    var isProvisional: Bool
}

@main enum PreviewSurfaceReplay {
    @MainActor static func main() throws {
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let events = value["publications"] as! [[String: Any]]
        let expected = (value["archive"] as! [String]).reversed().joined()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            var results: [[String: Any]] = []
            for mode in ["following", "reading", "selection", "editing", "hidden", "controlOnly"] {
            for width in [180.0, 260.0, 360.0] {
                let panel = NSPanel(contentRect: .init(x: -2000, y: -2000, width: width, height: 200),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.ignoresMouseEvents = true
                let view = CompactTranscriptScrollView<SurfaceRow>(frame: .init(x: 0, y: 0, width: width, height: 200))
                view.transcriptView.isEditable = true
                view.transcriptView.showsLiveCaret = true
                view.applyEdits = { _ in fatalError("No input is authorized in this fixture") }
                panel.contentView = view
                panel.orderFrontRegardless()
                let id = UUID()
                var checks: [[String: Any]] = []
                for (index, event) in events.enumerated() {
                    if index == 3 {
                        view.settleLivePresentation()
                        switch mode {
                        case "reading": view.focus(on: 1)
                        case "selection": view.transcriptView.setSelectedRange(NSRange(location: 0, length: 2))
                        case "editing": view.editing = true
                        case "hidden": panel.orderOut(nil)
                        case "controlOnly": view.setControlOnly(true)
                        default: break
                        }
                    }
                    let held = index >= 3 && ["selection", "editing", "controlOnly"].contains(mode)
                    let snapshot = view.transcriptView.string
                    let text = event["text"] as! String
                    let row = SurfaceRow(id: id, displayText: text, isProvisional: index < events.count - 1)
                    var document = PanelTimelineDocument(entries: [row])
                    document.liveTailID = row.isProvisional ? id : nil
                    view.updateDocument(document)
                    try? await Task.sleep(for: .milliseconds(120))
                    checks.append(["expected": text, "actual": view.transcriptView.string,
                                   "selectedLength": view.transcriptView.selectedRange().length,
                                   "editing": view.editing, "deferred": view.hasDeferredUpdate,
                                   "blocker": view.presentationBlocker ?? "none",
                                   "pass": view.transcriptView.string == (held ? snapshot : text)])
                }
                // Release only the deliberately held fixture interaction. This
                // is not a retry of the original failed native run.
                view.editing = false
                view.setControlOnly(false)
                view.transcriptView.setSelectedRange(NSRange(location: 0, length: 0))
                panel.orderFrontRegardless()
                view.settleLivePresentation()
                try? await Task.sleep(for: .milliseconds(120))
                results.append(["mode": mode, "width": width, "checks": checks,
                                "finalMatchesArchive": view.transcriptView.string == expected])
                panel.close()
            }
            }
            let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            app.terminate(nil)
        }
        app.run()
    }
}
