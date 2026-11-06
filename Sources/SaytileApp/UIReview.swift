import AppKit
import SwiftUI
import AVFoundation
import SaytileKit

// Runs only with --ui-review AND an explicitly isolated data directory. All text/audio is synthetic.
extension AppDelegate {
    @MainActor func runUIReview(model: AppModel, output: URL) async {
        NSApp.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            await model.initialLoad()
            guard model.records.isEmpty else { throw NSError(domain: "Saytile.UIReview", code: 2, userInfo: [NSLocalizedDescriptionKey: "UI review requires an empty isolated data directory"]) }
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 400, height: 550), name: "panel-empty", output: output)
            let examples = [
                "周五的产品讨论，先把重点记下来。保持表达自然，停顿之后还可以继续。",
                "这周想留一点时间，把散落的想法整理成一页清晰的计划。不要自动发送，确认之后再决定。",
                "API、Swift 与中文可以放在同一段表达里。测试 emoji 😀，保留所有修改版本。"
            ]
            for (index, text) in examples.enumerated() {
                let row = try await model.store.createRecording(createdAt: Date().addingTimeInterval(Double(index)))
                _ = try await model.store.saveEdit(recordingID: row.id, text: text)
                try await model.store.finishRecording(id: row.id)
                if index == 1 { try await model.store.setPinned(recordingID: row.id, pinned: true) }
                if index == 2 { try await model.store.deleteAudio(recordingID: row.id) }
            }
            await model.refresh()
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 400, height: 550), name: "panel-content", output: output) { host in
                try await self.press("直接输入", in: host)
                guard model.directMode else { throw ReviewFailure("direct mode button did not change mode") }
                try await self.press("自由记录", in: host)
                guard !model.directMode else { throw ReviewFailure("free record button did not restore mode") }
                print("UI_CONTROL_PASS mode buttons through native control events")
            }
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 400, height: 440), name: "panel-compact", output: output)
            try await reviewWindow(ArchiveView(model: model), size: CGSize(width: 1040, height: 720), name: "archive", output: output) { host in
                try await self.press("已收藏", in: host)
                await model.refresh()
                guard model.recordFilter == .pinned, model.records.count == 1 else { throw ReviewFailure("native archive filter action failed: filter=\(model.recordFilter), count=\(model.records.count)") }
                try await self.press("全部记录", in: host)
                await model.refresh()
                guard model.records.count == 3 else { throw ReviewFailure("native archive all-records action failed") }
                print("UI_CONTROL_PASS archive filters through native control events and SQLite")
            }
            if let row = model.records.first {
                await model.selectForEditing(row)
                model.updateEditorDraft(row.text + "\n这是会自动保留的编辑草稿。")
                _ = await model.flushEditorDrafts()
                try await reviewWindow(ArchiveView(model: model), size: CGSize(width: 1120, height: 720), name: "archive-detail", output: output) { host in
                    try await self.press("保存修改", in: host)
                    for _ in 0..<50 {
                        if (try await model.store.recording(id: row.id))?.text.contains("自动保留的编辑草稿") == true { break }
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    guard (try await model.store.recording(id: row.id))?.text.contains("自动保留的编辑草稿") == true else { throw ReviewFailure("native save action did not commit edit") }
                    print("UI_CONTROL_PASS native Save action commits immutable edit")
                }
                try await reviewWindow(ArchiveView(model: model), size: CGSize(width: 1120, height: 570), name: "archive-detail-compact", output: output)
                model.closeDetail()
            }
            model.query = "找不到的合成关键词"; await model.refresh()
            try await reviewWindow(ArchiveView(model: model), size: CGSize(width: 1040, height: 720), name: "archive-no-results", output: output)
            model.query = ""; model.notice = nil
            try await reviewWindow(SettingsView(model: model), size: CGSize(width: 650, height: 740), name: "settings", output: output)
            try await reviewWindow(SettingsView(model: model), size: CGSize(width: 560, height: 570), name: "settings-compact", output: output)
            if ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] == nil { print("UI_CONTROLS_NOT_RUN remote AX helper not configured; rendering only") }
            print("UI_REVIEW_PASS native SwiftUI attached to AppKit windows; 9 captures; synthetic data; no activation/microphone")
        } catch { print("UI_REVIEW_FAILED \(error.localizedDescription)") }
    }

    private struct ReviewFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
    @MainActor private func press(_ label: String, in root: NSView) async throws {
        guard let path = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"], let window = root.window else { throw ReviewFailure("Native UI control helper not configured") }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), label, window.title]
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let result = await Task.detached {
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: output, as: UTF8.self))
        }.value
        print(result.1.trimmingCharacters(in: .whitespacesAndNewlines))
        guard result.0 == 0 else { throw ReviewFailure("Remote native AX action failed for \(label), code=\(result.0)") }
        try await Task.sleep(for: .milliseconds(80))
    }
    @MainActor private func reviewWindow<V: View>(_ content: V, size: CGSize, name: String, output: URL, interaction: (@MainActor (NSView) async throws -> Void)? = nil) async throws {
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: 0, y: 0), size: size),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Saytile UI Review " + name
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: content.preferredColorScheme(.light))
        panel.contentView = host
        panel.setContentSize(size)
        panel.makeFirstResponder(host)
        panel.orderBack(nil)
        defer { panel.orderOut(nil); panel.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        if let interaction, ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil { try await interaction(host); try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded() }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: output.appendingPathComponent(name + ".png"))
        guard before == NSWorkspace.shared.frontmostApplication?.processIdentifier else { throw NSError(domain: "Saytile.UIReview", code: 1, userInfo: [NSLocalizedDescriptionKey: "UI review changed the foreground application"] ) }
        print("UI_CAPTURE \(name) \(Int(host.bounds.width))x\(Int(host.bounds.height)) foreground_unchanged=true")
    }
}
