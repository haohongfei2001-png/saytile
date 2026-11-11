import AppKit
import Combine
import SwiftUI
import AVFoundation
import SaytileKit

// Runs only with --ui-review AND an explicitly isolated data directory. All text/audio is synthetic.
extension AppDelegate {
    @MainActor func runUIReview(model: AppModel, output: URL) async -> Bool {
        let timeline = ProcessInfo.processInfo.environment["SAYTILE_TIMELINE_REVIEW"] == "1"
        NSApp.setActivationPolicy(timeline ? .accessory : .prohibited)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            if ProcessInfo.processInfo.environment["SAYTILE_REFERENCE_ONLY"] == "1" {
                try await reviewApprovedReference(output: output)
                print("REFERENCE_REVIEW_PASS isolated production window; synthetic capture only")
                return true
            }
            await model.initialLoad()
            if ProcessInfo.processInfo.environment["SAYTILE_TIMELINE_REVIEW"] == "1" {
                try await reviewTimeline(model: model, output: output)
                return true
            }
            guard model.records.isEmpty else { throw NSError(domain: "Saytile.UIReview", code: 2, userInfo: [NSLocalizedDescriptionKey: "UI review requires an empty isolated data directory"]) }
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240), name: "panel-empty", output: output)
            let examples = [
                "周五的产品讨论，先把重点记下来。保持表达自然，停顿之后还可以继续。",
                "这周想留一点时间，把散落的想法整理成一页清晰的计划。不要自动发送，确认之后再决定。",
                "API、Swift 与中文可以放在同一段表达里。测试 emoji 😀，只显示一份持续修正的文字。"
            ]
            for (index, text) in examples.enumerated() {
                let row = try await model.store.createRecording(createdAt: Date().addingTimeInterval(Double(index)))
                _ = try await model.store.saveEdit(recordingID: row.id, text: text)
                try await model.store.finishRecording(id: row.id)
                if index == 1 { try await model.store.setPinned(recordingID: row.id, pinned: true) }
                if index == 2 { try await model.store.deleteAudio(recordingID: row.id) }
            }
            await model.refresh()
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240), name: "panel-content", output: output) { host in
                try await self.selectMenu("direct", title: "直接输入", in: host)
                try await self.reviewUntil { model.directMode }
                guard model.directMode else { throw ReviewFailure("direct mode button did not change mode") }
                print("UI_NATIVE_MENU_ACK direct_mode=true")
                try await self.selectMenu("free", title: "自由记录", in: host)
                try await self.reviewUntil { !model.directMode }
                guard !model.directMode else { throw ReviewFailure("free record button did not restore mode") }
                print("UI_NATIVE_MENU_ACK direct_mode=false")
                print("UI_CONTROL_PASS modes through real native transcript context menu actions")
            }
            try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 320, height: 200), name: "panel-compact", output: output)
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
            await model.refresh()
            if let row = model.records.first(where: { $0.source.audioState == .available }) {
                let ticket = try await model.store.beginFusionRecognition(recordingID: row.id)
                let review = ModelConfiguration(purpose: .textFusion, provider: .openAIResponses, model: "gpt-6-astra")
                let run = try await model.store.beginModelRun(ticket: ticket, configuration: review)
                await model.refresh()
                guard let active = model.recent.first(where: { $0.id == row.id }),
                      model.recognitionPhaseLabel(for: active) == "正在核对文字",
                      active.text == row.text, model.recent.filter({ $0.id == row.id }).count == 1 else {
                    throw ReviewFailure("single transcript or generic processing state was not retained")
                }
                try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 360, height: 260), name: "panel-ai-review", output: output)
                try await model.store.finishModelRun(run, error: "合成复核连接中断", retryable: true)
                try await model.store.failRecognition(ticket: ticket, message: "合成复核连接中断，原音与文字已保留")
                await model.refresh()
                guard let failed = model.recent.first(where: { $0.id == row.id }),
                      model.recognitionPhaseLabel(for: failed) == "识别待恢复", failed.text == row.text else {
                    throw ReviewFailure("failed review changed existing text or retained stale running phase")
                }
                try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 360, height: 260), name: "panel-ai-recovery", output: output)
                print("UI_STATE_PASS one transcript survives single-core processing and failure; synthetic Store runs, no providers")
            }
            try await reviewWindow(SettingsView(model: model), size: CGSize(width: 650, height: 740), name: "settings", output: output)
            try await reviewWindow(SettingsView(model: model), size: CGSize(width: 560, height: 570), name: "settings-compact", output: output)
            model.selectSource("hosted")
            try await reviewWindow(SettingsView(model: model), size: CGSize(width:650,height:740), name:"settings-hosted", output:output) { host in
                guard model.hosted.selected, !model.hosted.consent, !model.hosted.signedIn else {throw ReviewFailure("unexpected hosted consent")}
                if ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil {
                    try await self.press("hosted.upload-consent", in:host)
                    try await self.reviewUntil { model.hosted.consent }
                    try await self.press("hosted.upload-consent", in:host)
                    try await self.reviewUntil { !model.hosted.consent }
                }
            }
            model.selectSource("local")
            try await reviewWindow(Form { RecognitionSettingsSection(model: model) }.formStyle(.grouped), size: CGSize(width: 650, height: 840), name: "ai-controls", output: output) { host in
                guard !model.connectionVerified, !model.recognitionConfiguration.cloudEnabled else {
                    throw ReviewFailure("unconfigured cloud connection was enabled")
                }
                try await self.press("recognition.configureServices", in: host)
                guard !model.connectionCheckAuthorized else { throw ReviewFailure("cost authorization was preselected") }
                try await self.press("connection.authorizeCheck", in: host)
                guard model.connectionCheckAuthorized, !model.checkingConnection,
                      !model.appliedRecognitionConfiguration.cloudEnabled else {
                    throw ReviewFailure("cost consent started a connection or enabled cloud without prepared services")
                }
                model.recognitionSettingsNotice = nil
                try await self.press("recognition.apply", in: host)
                for _ in 0..<100 {
                    if !model.applyingRecognitionSettings, model.recognitionSettingsNotice != nil { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                guard !model.appliedRecognitionConfiguration.cloudEnabled, model.recognitionSettingsNotice != nil else {
                    throw ReviewFailure("unconfigured settings enabled cloud")
                }
                try await self.setValue("合成界面测试话题", for: "recognition.topicContext", in: host)
                guard model.recognitionConfiguration.topicContext == "合成界面测试话题" else { throw ReviewFailure("native topic field did not update draft") }
                try await self.press("recognition.apply", in: host)
                for _ in 0..<100 {
                    if !model.applyingRecognitionSettings, model.appliedRecognitionConfiguration.topicContext == "合成界面测试话题" { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                guard model.appliedRecognitionConfiguration.topicContext == "合成界面测试话题",
                      !model.appliedRecognitionConfiguration.cloudEnabled, !model.hasUnappliedRecognitionSettings else {
                    throw ReviewFailure("native settings apply did not commit isolated local configuration")
                }
                print("UI_CONTROL_PASS recognition settings: unverified cloud disabled, explicit cost authorization, offline apply and native text edit")
            }
            try await reviewWindow(Form { RecognitionSettingsSection(model: model, initiallyExpanded: true) }.formStyle(.grouped), size: CGSize(width: 650, height: 840), name: "ai-services", output: output)
            if !model.recognitionConfiguration.models.isEmpty {
                try await reviewWindow(Form {
                    Section("中文专家设置") {
                        ModelConfigurationEditor(configuration: Binding(get: { model.recognitionConfiguration.models[0] }, set: { model.recognitionConfiguration.models[0] = $0 }), model: model, initiallyExpanded: true)
                    }
                }.formStyle(.grouped), size: CGSize(width: 650, height: 740), name: "ai-chinese-keychain", output: output) { host in
                    let prefix = "recognition.model." + model.recognitionConfiguration.models[0].id.uuidString.lowercased()
                    guard model.recognitionConfiguration.models[0].enabled else { throw ReviewFailure("required expert unexpectedly disabled") }
                    try await self.setValue("synthetic-workspace", for: prefix + ".workspace", in: host)
                    guard model.recognitionConfiguration.models[0].workspaceID == "synthetic-workspace" else { throw ReviewFailure("native workspace field failed") }
                    try await self.press(prefix + ".consent", in: host)
                    guard model.recognitionConfiguration.models[0].cloudConsent else { throw ReviewFailure("native processing consent toggle failed") }
                    try await self.press(prefix + ".consent", in: host)
                    guard !model.recognitionConfiguration.models[0].cloudConsent,
                          model.recognitionConfiguration.models[0].enabled else { throw ReviewFailure("native model controls did not restore safe defaults") }
                    print("UI_CONTROL_PASS single selected ASR + GPT setup: workspace and per-service consent; no model toggle, key read or cloud request")
                }
            }
            let setupRoot = output.appendingPathComponent("connection-setup-" + UUID().uuidString, isDirectory: true)
            let setup = try ConnectionSetupRequest(directory: setupRoot, output: setupRoot.appendingPathComponent("configuration.json"))
            var setupFinished = false
            try await reviewWindow(ConnectionSetupView(model: model, request: setup, finish: { setupFinished = true }), size: CGSize(width: 650, height: 840), name: "connection-setup", output: output) { host in
                try await self.press("connectionSetup.finish", in: host)
                guard !setupFinished, !FileManager.default.fileExists(atPath: setup.output.path) else {
                    throw ReviewFailure("unready connection setup exported configuration or finished")
                }
                print("UI_CONTROL_PASS isolated setup rejects unfinished configuration through native Finish action; no export or provider request")
            }
            try await reviewFirstConnection(output: output)
            try await reviewCompactPanel(output: output)
            try reviewVoiceGlyph(output: output)
            let referenceOutput = output.appendingPathComponent("approved-reference", isDirectory: true)
            try FileManager.default.createDirectory(at: referenceOutput, withIntermediateDirectories: true)
            try await reviewApprovedReference(output: referenceOutput)
            if ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] == nil { print("UI_CONTROLS_NOT_RUN remote AX helper not configured; rendering only") }
            let captures = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] == nil ? 28 : 38
            print("UI_REVIEW_PASS native SwiftUI attached to AppKit windows; \(captures) standard captures plus 3 approved-reference captures; synthetic data; no activation/microphone")
            return true
        } catch { print("UI_REVIEW_FAILED \(error.localizedDescription)"); return false }
    }

    /// Runs only against the disposable seed prepared by test-native-timeline.py.
    @MainActor private func reviewTimeline(model: AppModel, output: URL) async throws {
        guard model.timelineTail?.position == 12000, let board = model.copyPasteboard,
              board.name != NSPasteboard.general.name, !model.directMode, model.audio.state == .paused else {
            throw ReviewFailure("expected private board, isolated 12000-row timeline and paused capture")
        }
        defer { board.releaseGlobally() }
        model.changeIdleInterval(10)
        try await reviewUntil { model.timelineIdleSeconds == 10 }
        let start = Date.now
        let first = try await model.store.createRecording(createdAt: start)
        let ticket = try await model.store.beginRecognition(recordingID: first.id)
        try await model.store.applyRecognition(ticket: ticket, text: "想把这个想法记下来。", isFinal: false)
        try await model.store.finishRecording(id: first.id, speechEndedAt: start)
        let second = try await model.store.createRecording(createdAt: start.addingTimeInterval(0.2))
        let continuation = "嗯，先不发，明天再看。"
        try await model.store.saveEdit(recordingID: second.id, text: continuation)
        try await model.store.finishRecording(id: second.id, speechEndedAt: start.addingTimeInterval(0.2))
        await model.refresh()
        let initialText = "想把这个想法记下来。"
        let controls = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil
        try await reviewValidatedWindow(InputPanelWindowView(model: model), size: WindowPlacement.panelDefaultSize,
            name: "timeline-history", output: output, validation: { host in
                let scroll = try self.compactTranscript(in: host)
                guard scroll.rendered.spans.count == 64,
                      scroll.rendered.spans.suffix(2).map({ $0.entry.id }) == [first.id,second.id],
                      scroll.rendered.spans.suffix(2).allSatisfy({ $0.entry.group == model.timelineTail?.group }) else {
                    throw ReviewFailure("continuous native timeline did not load newest group")
                }
                try self.captureReview(host, name: "timeline-live", output: output)
                if controls {
                    try await self.press("panel.copy", in: host)
                    guard board.string(forType: .string) == initialText + "\n" + continuation else { throw ReviewFailure("copy scope was not latest group") }
                }
                let changes = board.changeCount
                try await model.store.applyRecognition(ticket: ticket, text: "想把这段话记下来。", isFinal: true)
                await model.refresh()
                try await self.reviewUntil { scroll.rendered.spans.suffix(2).first?.entry.recording.text == "想把这段话记下来。" }
                guard board.changeCount == changes, scroll.rendered.spans.last?.entry.id == second.id else { throw ReviewFailure("late revision changed clipboard or order") }
                await model.selectForEditing(DisplayRecording(source: first))
                model.updateEditorDraft("用户自己决定的写法")
                try await model.store.applyRecognition(ticket: ticket, text: "迟到的候选版本", isFinal: true)
                await model.refresh()
                guard model.editorDraft == "用户自己决定的写法" else { throw ReviewFailure("late ASR rewrote unsaved edit") }
                model.closeDetail()
                let beforeIdle = scroll.contentView.bounds.minY
                // Wait for the actual production timer at the shortest supported interval.
                if ProcessInfo.processInfo.environment["SAYTILE_RECORD_TIMELINE"] == "1" {
                    try await self.recordIdleTransition(host, model: model, output: output)
                } else {
                    for _ in 0..<140 where !model.timelineIdle { try await Task.sleep(for: .milliseconds(100)) }
                }
                // The final easing step can be less than one point. Capture the
                // anchor only after the clip reaches the actual layout destination.
                try await self.reviewUntil { scroll.rendered.idle && scroll.contentView.bounds.minY > beforeIdle + 20 &&
                    scroll.contentView.bounds.minY == max(0, scroll.transcriptView.bounds.height - scroll.contentSize.height) }
                try self.captureReview(host, name: "timeline-idle", output: output)
                if controls {
                    let anchor = scroll.contentView.bounds.origin
                    let state = model.audio.state
                    let notice = model.notice
                    let expected = try await model.store.recording(id: first.id)!.text + "\n" + continuation
                    try await self.press("panel.copy", in: host)
                    guard board.string(forType: .string) == expected, model.timelineIdle,
                          scroll.contentView.bounds.origin == anchor, scroll.selectionSnapshot.isEmpty,
                          model.audio.state == state, model.notice == notice else {
                        throw ReviewFailure("idle click did not silently snapshot the latest group in place")
                    }
                    print("IDLE_COPY_PASS two utterances; blank viewport, capture and notice unchanged")
                }
                let idleClipboard = board.changeCount
                // The archive editor holds its page, as on a nonactivating panel click.
                await model.selectForEditing(DisplayRecording(source: first))
                model.archiveIsKey = true
                model.updateEditorDraft("独立复核的未提交草稿")
                try await self.reviewUntil { scroll.editing }
                let new = try await model.store.createRecording()
                try await model.store.saveEdit(recordingID: new.id, text: "再记一句，和之前的想法放在一起。")
                try await model.store.finishRecording(id: new.id)
                await model.refresh()
                guard board.changeCount == idleClipboard else { throw ReviewFailure("new speech rewrote an idle clipboard snapshot") }
                if controls {
                    guard scroll.rendered.idle, scroll.rendered.spans.last?.entry.id == second.id else {
                        throw ReviewFailure("editor failed to hold the idle reading page")
                    }
                    try await self.press("panel.copy", in: host)
                    guard board.string(forType: .string) == "再记一句，和之前的想法放在一起。",
                          model.editorDraft == "独立复核的未提交草稿", scroll.rendered.idle else {
                        throw ReviewFailure("copy on a held blank panel used the previous group")
                    }
                    print("HELD_IDLE_COPY_PASS newest group only; editor draft and held viewport intact")
                }
                model.archiveIsKey = false
                model.closeDetail()
                try await self.reviewUntil { !scroll.rendered.idle && scroll.rendered.spans.last?.entry.id == new.id }
                guard model.timelineTail?.group != scroll.rendered.spans.dropLast().last?.entry.group else { throw ReviewFailure("post-idle speech reused previous group") }
                // Deliver an AppKit wheel event directly to our own scroll view.
                // No global event, active application, public clipboard or microphone.
                let oldFirst = scroll.rendered.firstPosition!
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
                guard let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 320, wheel2: 0, wheel3: 0),
                      let event = NSEvent(cgEvent: wheel) else { throw ReviewFailure("no native wheel event") }
                let began = ContinuousClock.now
                // A real trackpad gesture can span multiple Cocoa run-loop turns.
                // The native view must cross the old keyset boundary and retain overlap.
                for _ in 0..<12 where scroll.rendered.firstPosition == oldFirst {
                    scroll.scrollWheel(with: event)
                    try await Task.sleep(for: .milliseconds(20))
                }
                try await self.reviewUntil { (scroll.rendered.firstPosition ?? oldFirst) < oldFirst }
                guard scroll.rendered.spans.count == 64, !scroll.isFollowingLatest,
                      scroll.rendered.spans.contains(where: { $0.entry.position == oldFirst }) else { throw ReviewFailure("paged native viewport dropped overlap") }
                print("TIMELINE_NATIVE_PAGE rows=12003 resident=64 wheel_to_paint=\(began.duration(to: .now))")
                let dateMarkers = scroll.rendered.markers.filter { range in
                    (scroll.transcriptView.string as NSString).substring(with: range).hasPrefix("2025-01-")
                }
                guard dateMarkers.count == 2, let midnight = dateMarkers.last else { throw ReviewFailure("midnight did not introduce local date marker") }
                scroll.transcriptView.scrollRangeToVisible(midnight)
                try self.captureReview(host, name: "timeline-midnight", output: output)
                // Select a line already on screen. A second asynchronous AppKit scroll
                // would still be moving the viewport when the history check starts.
                guard let layout = scroll.transcriptView.layoutManager,
                      let container = scroll.transcriptView.textContainer,
                      let span = scroll.rendered.spans.first(where: {
                          let glyphs = layout.glyphRange(forCharacterRange: $0.range, actualCharacterRange: nil)
                          var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
                          let origin = scroll.transcriptView.textContainerOrigin
                          rect = rect.offsetBy(dx: origin.x, dy: origin.y)
                          return scroll.documentVisibleRect.contains(rect)
                      }) else { throw ReviewFailure("no visible historical line to select") }
                scroll.transcriptView.setSelectedRange(span.range)
                let anchor = scroll.contentView.bounds.minY
                let last = try await model.store.createRecording()
                try await model.store.saveEdit(recordingID: last.id, text: "继续说，也留住刚才选中的文字。")
                try await model.store.finishRecording(id: last.id)
                await model.refresh()
                guard scroll.selectionSnapshot == span.entry.recording.text, abs(anchor - scroll.contentView.bounds.minY) < 1,
                      !model.recent.contains(where: { $0.id == span.entry.id }) else { throw ReviewFailure("history selection moved or entered insertion list") }
                if controls {
                    try await self.press("panel.copy", in: host)
                    guard board.string(forType: .string) == span.entry.recording.text else { throw ReviewFailure("historical selection copy failed") }
                }
                print("TIMELINE_NATIVE_PASS idle_before_y=\(beforeIdle) selected=stable private_board=\(controls) history_isolated=true")
            })
        model.followTimeline()
        await model.refresh()
        try await reviewValidatedWindow(InputPanelWindowView(model: model), size: WindowPlacement.panelDefaultSize,
            name: "timeline-reopened", output: output, validation: { host in
                let scroll = try self.compactTranscript(in: host)
                guard scroll.isFollowingLatest, scroll.rendered.spans.last?.entry == model.timelineTail,
                      scroll.rendered.spans.count == 64 else { throw ReviewFailure("reopened window lost live timeline") }
            })
    }

    /// Record only this process's real native view during the production idle
    /// transition. Keep pre-transition frames in a short rolling buffer.
    @MainActor private func recordIdleTransition(_ host: NSView, model: AppModel, output: URL) async throws {
        let directory = output.appendingPathComponent("motion-frames")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var frames: [(time: Double, png: Data)] = []
        let start = ProcessInfo.processInfo.systemUptime
        var idleAt: Double?
        while ProcessInfo.processInfo.systemUptime - start < 16 {
            guard let window = host.window, window is ReviewPanel, !window.isKeyWindow,
                  let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw ReviewFailure("native view recording unavailable") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let time = ProcessInfo.processInfo.systemUptime
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ReviewFailure("native frame unavailable") }
            frames.append((time, png))
            if model.timelineIdle && idleAt == nil { idleAt = time }
            if let idleAt {
                if time - idleAt > 0.65 { break }
            } else { frames.removeAll { time - $0.time > 0.5 } }
            try await Task.sleep(for: .milliseconds(16))
        }
        guard idleAt != nil, let first = frames.first else { throw ReviewFailure("idle transition missing from recording") }
        for (i, frame) in frames.enumerated() {
            try frame.png.write(to: directory.appendingPathComponent("\(i).png"))
        }
        try JSONEncoder().encode(frames.map { $0.time - first.time }).write(to: directory.appendingPathComponent("times.json"))
    }

    private struct ReviewFailure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
    @MainActor private func press(_ label: String, in root: NSView) async throws {
        _ = try await performControl(label, in: root)
    }
    @MainActor private func selectMenu(_ id: String, title: String, in root: NSView, hostID: String = "panel.transcript") async throws {
        let identifier = (hostID == "panel.copy" ? "panel.more." : "panel.menu.") + id
        let output = try await performControl(hostID, in: root, arguments: ["select-context-menu", identifier, title])
        guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix("NATIVE_UI_CONTEXT_ITEMS ") }),
              let ids = try JSONSerialization.jsonObject(with: Data(line.dropFirst("NATIVE_UI_CONTEXT_ITEMS ".count).utf8)) as? [String],
              ids.contains(hostID == "panel.copy" ? "panel.more.bind" : "panel.menu.bind"),
              ids.contains(hostID == "panel.copy" ? "panel.more.insert" : "panel.menu.insert") else {
            throw ReviewFailure("native transcript menu did not retain explicit bind/insert commands")
        }
    }
    @MainActor private func checkPrivateCopy(_ expected: String, board: NSPasteboard,
        capture: UIPanelCaptureFixture, model: AppModel, host: NSView) async throws {
        let previousCount = board.changeCount
        let starts = capture.starts, pauses = capture.pauses, state = capture.state
        var receivedSuccess = false
        let observation = model.$notice.sink { message in
            if message == "已复制，可以粘贴到任何应用。" { receivedSuccess = true }
        }
        defer { observation.cancel() }
        try await press("panel.copy", in: host)
        guard let copied = board.string(forType: .string), copied.utf16.elementsEqual(expected.utf16),
              board.changeCount > previousCount, capture.starts == starts, capture.pauses == pauses, capture.state == state else {
            throw ReviewFailure("copy changed capture or did not write the exact expected text to the unique pasteboard")
        }
        // Panel copy is silent, including while the private pasteboard is written.
        guard !receivedSuccess else { throw ReviewFailure("panel copy displayed unsolicited success feedback") }
    }

    @MainActor private func setValue(_ value: String, for label: String, in root: NSView, secure: Bool = false) async throws {
        _ = try await performControl(label, in: root, arguments: ["set-value", value])
        // AXSetValue changes the AppKit presentation but does not necessarily send
        // SwiftUI's editing delegate events. Exercise the real, window-owned editor
        // to commit the same synthetic value; never call the model or post keys.
        var queue = [root], matching: [NSTextField] = []
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let field = view as? NSTextField, (field is NSSecureTextField) == secure, field.stringValue == value {
                matching.append(field)
            }
            queue += view.subviews
        }
        guard matching.count == 1, let field = matching.first, let window = root.window,
              field.window === window else {
            throw ReviewFailure("unique native field unavailable for \(label)")
        }
        try checkKeyboardIsolation(window, phase: "before-field-edit")
        guard window.makeFirstResponder(field),
              let editor = window.fieldEditor(false, for: field) as? NSTextView else {
            throw ReviewFailure("unique native field editor unavailable for \(label)")
        }
        editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        _ = window.makeFirstResponder(root)
        try await Task.sleep(for: .milliseconds(80))
        try checkKeyboardIsolation(window, phase: "after-field-edit")
        print("NATIVE_UI_FIELD_EDIT \(label) via owned NSTextView delegate; no global key events")
        if secure { print("NATIVE_UI_SECURE_FIELD_EDIT \(label) fixture credential only; value omitted") }
    }
    @MainActor private func performControl(_ label: String, in root: NSView, arguments: [String] = []) async throws -> String {
        guard let path = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"], let window = root.window else { throw ReviewFailure("Native UI control helper not configured") }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), label, window.title]
        process.arguments! += arguments
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
        return result.1
    }
    @MainActor private func reviewWindow<V: View>(_ content: V, size: CGSize, name: String, output: URL,
        interaction: (@MainActor (NSView) async throws -> Void)? = nil) async throws {
        // Keep legacy trailing closures unambiguously control-only. Rendering checks use
        // a distinct entry point so an optional closure cannot bind to validation.
        try await reviewValidatedWindow(content, size: size, name: name, output: output,
                                        validation: nil, interaction: interaction)
    }
    @MainActor private func reviewValidatedWindow<V: View>(_ content: V, size: CGSize, name: String, output: URL,
        validation: (@MainActor (NSView) async throws -> Void)? = nil,
        interaction: (@MainActor (NSView) async throws -> Void)? = nil) async throws {
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let activations = ReviewActivations(ownPID: ownPID)
        let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                activations.record(pid: app.processIdentifier)
            }
        }
        defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        let panel = ReviewPanel(contentRect: CGRect(origin: CGPoint(x: 0, y: 0), size: size),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Saytile UI Review " + name
        // A fully transparent panel may disappear from AXWindows while idle.
        // Keep the timeline fixture drawable outside every display, without taking focus.
        let offscreen = name.hasPrefix("timeline-")
        panel.alphaValue = offscreen ? 1 : 0
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: content.preferredColorScheme(.light))
        panel.contentView = host
        panel.setContentSize(size)
        if offscreen {
            let right = NSScreen.screens.map { $0.frame.maxX }.max() ?? 0
            panel.setFrameOrigin(NSPoint(x: right + 64, y: 0))
            guard NSScreen.screens.allSatisfy({ !$0.frame.intersects(panel.frame) }) else {
                throw ReviewFailure("timeline fixture intersects a physical display")
            }
        }
        panel.makeFirstResponder(host)
        panel.orderBack(nil)
        defer { panel.orderOut(nil); panel.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        if name.hasPrefix("panel-") {
            guard (320...360).contains(host.bounds.width), (200...480).contains(host.bounds.height),
                  abs(host.bounds.width - size.width) < 1, abs(host.bounds.height - size.height) < 1 else {
                throw ReviewFailure("compact panel exceeded its requested native geometry")
            }
        }
        try checkKeyboardIsolation(panel, phase: "before-validation")
        if let validation { try await validation(host); host.layoutSubtreeIfNeeded() }
        try checkKeyboardIsolation(panel, phase: "after-validation")
        if let interaction, ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil { try await interaction(host); try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded() }
        try checkKeyboardIsolation(panel, phase: "after-interaction")
        try captureReview(host, name: name, output: output)
        let after = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard !activations.candidateActivated, after != ownPID else {
            throw ReviewFailure("candidate activated during \(name); other_activation_events=\(activations.otherActivations)")
        }
        if before != after || activations.otherActivations > 0 {
            print("UI_FOREGROUND_OBSERVATION \(name) candidate_activated=false outside_activation_events=\(activations.otherActivations); unrelated transition retained, no cause inferred")
        }
        print("UI_CAPTURE \(name) \(Int(host.bounds.width))x\(Int(host.bounds.height)) foreground_unchanged=\(before == after) candidate_activated=false")
    }

    @MainActor private func checkKeyboardIsolation(_ window: NSWindow, phase: String) throws {
        guard window is ReviewPanel, !window.canBecomeKey, !window.canBecomeMain,
              !window.isKeyWindow, !window.isMainWindow else {
            throw ReviewFailure("native review window violated keyboard isolation during \(phase)")
        }
        print("UI_KEYBOARD_ISOLATION \(phase) can_become_key=false can_become_main=false is_key=false is_main=false")
    }

    @MainActor private func captureReview(_ host: NSView, name: String, output: URL) throws {
        guard let window = host.window else { throw ReviewFailure("native capture window unavailable") }
        try checkKeyboardIsolation(window, phase: "capture")
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: output.appendingPathComponent(name + ".png"))
        let geometry: [String: Any] = ["name": name, "width_points": host.bounds.width, "height_points": host.bounds.height,
                                      "width_pixels": bitmap.pixelsWide, "height_pixels": bitmap.pixelsHigh]
        print("UI_IMAGE_GEOMETRY " + String(decoding: try JSONSerialization.data(withJSONObject: geometry, options: [.sortedKeys]), as: UTF8.self))
    }

    @MainActor private func reviewUntil(line: Int = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ReviewFailure("native UI controller did not acknowledge the expected state at UIReview.swift:\(line) within five seconds")
    }

    @MainActor private func inspectCapture(_ label: String, state: String, hasText: Bool = false, in host: NSView) async throws {
        let output = try await performControl("panel.capture", in: host, arguments: ["inspect-panel"])
        guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix("NATIVE_UI_PANEL_INSPECT ") }),
              let detail = try JSONSerialization.jsonObject(with: Data(line.dropFirst("NATIVE_UI_PANEL_INSPECT ".count).utf8)) as? [String: Any],
              let controls = detail["controls"] as? [[String: Any]],
              let scrollbarParts = detail["native_scrollbar_parts"] as? [[String: Any]],
              scrollbarParts.allSatisfy({ ($0["ancestor_roles"] as? [String])?.contains("AXScrollBar") == true }),
              let visibleStateText = detail["static_state_text"] as? [String], visibleStateText.isEmpty,
              let obsolete = detail["obsolete_state_identifiers"] as? [String], obsolete.isEmpty else {
            throw ReviewFailure("panel retained a visible state label or inspection was incomplete")
        }
        let captures = controls.filter { $0["identifier"] as? String == "panel.capture" }
        let copies = controls.filter { $0["identifier"] as? String == "panel.copy" }
        guard controls.count == 2, captures.count == 1, copies.count == 1,
              let capture = captures.first, let copy = copies.first,
              capture["role"] as? String == "AXButton", copy["role"] as? String == "AXButton",
              controls.filter({ $0["capture_action"] as? Bool == true }).count == 1,
              (capture["names"] as? [String])?.contains(label) == true,
              capture["value"] as? String == state, capture["enabled"] as? Bool == true, copy["enabled"] as? Bool == true,
              let cw = capture["width"] as? Double, let ch = capture["height"] as? Double, cw > ch,
              let copyHeight = copy["height"] as? Double, let copyWidth = copy["width"] as? Double,
              let x = capture["x"] as? Double, let left = copy["x"] as? Double,
              let y = capture["y"] as? Double, let copyY = copy["y"] as? Double,
              let windowX = detail["window_x"] as? Double, let windowY = detail["window_y"] as? Double,
              let windowWidth = detail["window_width"] as? Double, let windowHeight = detail["window_height"] as? Double,
              left + copyWidth < windowX + windowWidth / 2, x > windowX + windowWidth / 2,
              abs(y + ch / 2 - copyY - copyHeight / 2) < 2,
              (6...18).contains(windowY + windowHeight - y - ch),
              (6...18).contains(windowY + windowHeight - copyY - copyHeight) else {
            throw ReviewFailure("panel requires only a left copy button and right horizontal voice capsule on the bottom row")
        }
        // A native text document can be tall and scrolled. Check its actual
        // viewport in the host, not the full document's screen bounds.
        let scroll = try compactTranscript(in: host)
        let viewport = scroll.convert(scroll.bounds, to: host)
        let topInset = host.isFlipped ? viewport.minY - host.bounds.minY : host.bounds.maxY - viewport.maxY
        if state == "暂停" || state == "待命" || state == "正在识别" {
            guard topInset < ch, viewport.height > host.bounds.height / 2 else {
                throw ReviewFailure("normal compact panel retained a top toolbar or lost the transcript area")
            }
        }
        print("UI_BOTTOM_CONTROLS_PASS state=\(state) panel_buttons=2 left_copy=true right_voice_capsule=true visible_status_labels=0 has_text=\(hasText)")

    }

    @MainActor private func compactTranscript(in host: NSView) throws -> CompactTranscriptScrollView {
        var pending = [host], found: [CompactTranscriptScrollView] = []
        while !pending.isEmpty {
            let view = pending.removeFirst()
            if let transcript = view as? CompactTranscriptScrollView { found.append(transcript) }
            pending += view.subviews
        }
        guard found.count == 1, let result = found.first, result.window === host.window else {
            throw ReviewFailure("panel must contain one owned native transcript")
        }
        return result
    }

    /// Same shipping view and text renderer, on the exact measured card size.
    /// The new reference fixture supplements, never replaces, interaction tests.
    @MainActor private func reviewApprovedReference(output: URL) async throws {
        let suite = "app.saytile.test.reference." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-reference-" + UUID().uuidString)
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        var configuration = RecognitionConfiguration(); configuration.automaticRecovery = false
        try configuration.save(to: preferences)
        let capture = UIPanelCaptureFixture(), connection = UIConnectionFixture()
        let model = try AppModel(directory: directory, preferences: preferences,
            connectionDependencies: connection.dependencies, captureDependencies: capture.dependencies)
        await model.initialLoad()
        do {
            let row = try await model.store.createRecording()
            let text = "我想让 Saytile 成为一个始终待命\n的语音输入工作台，它应该让文字\n自然出现，而不是让按钮打断表达。\n说完这一句，它会安静地等我\n继续开口。"
            _ = try await model.store.saveEdit(recordingID: row.id, text: text)
            try await model.store.finishRecording(id: row.id)
            await model.refresh()
            for (name, state, level) in [("paused", CaptureState.paused, Float(0)),
                                          ("standby", CaptureState.listening, Float(0)),
                                          ("recognizing", CaptureState.speaking, Float(1))] {
                capture.state = state; capture.level = level; model.objectWillChange.send()
                try await reviewValidatedWindow(InputPanelWindowView(model: model),
                    size: WindowPlacement.panelDefaultSize, name: "reference-" + name, output: output,
                    validation: { host in
                        let scroll = try self.compactTranscript(in: host)
                        guard scroll.transcriptView.string.utf16.elementsEqual(text.utf16),
                              !scroll.transcriptView.isEditable, scroll.transcriptView.isSelectable,
                              model.audio.state == .paused else {
                            throw ReviewFailure("reference scene must use real selectable text without opening the microphone")
                        }
                        let viewport = scroll.convert(scroll.bounds, to: host)
                        let textView = scroll.transcriptView
                        let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                        guard font?.pointSize == ReferencePanelStyle.fontSize,
                              abs(viewport.width - 316) < 0.01,
                              textView.bounds.height <= scroll.contentSize.height + 1 else {
                            throw ReviewFailure("reference text metrics differ or the five-line reference clips")
                        }
                        print("REFERENCE_GEOMETRY state=\(name) window=408x298 card=344x234 font=\(font!.pointSize) viewport=\(viewport)")
                    })
            }
            await model.prepareForExit()
        } catch { await model.prepareForExit(); throw error }
    }

    @MainActor private func reviewCompactPanel(output: URL) async throws {
        let suite = "app.saytile.test.compact-panel." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-ui-panel-" + UUID().uuidString)
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        var configuration = RecognitionConfiguration(); configuration.automaticRecovery = false
        try configuration.save(to: preferences)
        let capture = UIPanelCaptureFixture(), connection = UIConnectionFixture()
        let copyBoard = NSPasteboard.withUniqueName()
        defer { copyBoard.releaseGlobally() }
        let model = try AppModel(directory: directory, preferences: preferences,
            connectionDependencies: connection.dependencies, captureDependencies: capture.dependencies, copyPasteboard: copyBoard)
        await model.initialLoad()
        let hasControls = ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil
        var emptyPanelSettings = 0
        model.openSettings = { emptyPanelSettings += 1 }
        do {
            try await reviewValidatedWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240),
                name: "panel-capture-initial", output: output, validation: { host in
                    guard model.panelCapturePresentation.state == .paused,
                          model.panelCapturePresentation.symbolName == "play.fill" else {
                        throw ReviewFailure("first use must share the paused play appearance")
                    }
                }, interaction: { host in
                    try await self.inspectCapture("开始收音", state: "暂停", in: host)
                    let before = copyBoard.changeCount
                    try await self.press("panel.copy", in: host)
                    guard copyBoard.changeCount == before, capture.starts == 0, capture.pauses == 0, model.notice == nil else {
                        throw ReviewFailure("empty copy changed the private pasteboard or capture state")
                    }
                    try await self.selectMenu("settings", title: "设置…", in: host, hostID: "panel.copy")
                    try await self.reviewUntil { emptyPanelSettings == 1 }
                    print("UI_EMPTY_PANEL_MENU_PASS empty copy is a no-op; its actual context menu opens settings")
                })

            if hasControls {
                try await reviewWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240),
                    name: "panel-capture-controls", output: output) { host in
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.starts == 1 && capture.state == .listening }
                    try await self.inspectCapture("暂停收音", state: "待命", in: host)
                    try self.captureReview(host, name: "panel-capture-listening", output: output)
                    let first = try await model.store.createRecording()
                    let firstTicket = try await model.store.beginRecognition(recordingID: first.id)
                    let partial = "不要支付15元。", final = "不要支付15元，Swift API 保留原文。"
                    guard try await model.store.applyRecognition(ticket: firstTicket, text: partial, isFinal: false) else {
                        throw ReviewFailure("synthetic partial did not reach the real Store")
                    }
                    capture.state = .speaking; capture.level = 0.35
                    await model.refresh(); model.objectWillChange.send()
                    guard model.panelCapturePresentation.liveVoiceLevel != nil else { throw ReviewFailure("injected speech level unavailable") }
                    try await self.inspectCapture("暂停收音", state: "正在识别", hasText: true, in: host)
                    try self.captureReview(host, name: "panel-capture-speaking", output: output)
                    try await model.store.finishRecording(id: first.id)
                    capture.state = .listening; capture.level = 0
                    await model.refresh(); model.objectWillChange.send()
                    guard try await model.store.recording(id: first.id)?.recognitionState == .running,
                          model.panelCapturePresentation.state == .standby, model.panelCapturePresentation.liveVoiceLevel == nil else {
                        throw ReviewFailure("VAD end waited for the running recognition ticket")
                    }
                    try await self.inspectCapture("暂停收音", state: "待命", hasText: true, in: host)
                    try self.captureReview(host, name: "panel-capture-vad-ended", output: output)
                    guard try await model.store.applyRecognition(ticket: firstTicket, text: final, isFinal: true) else {
                        throw ReviewFailure("background final text did not update the real Store")
                    }
                    await model.refresh()
                    let scroll = try self.compactTranscript(in: host)
                    try await self.reviewUntil { scroll.transcriptView.string.utf16.elementsEqual(final.utf16) }
                    guard model.recent.filter({ $0.id == first.id }).count == 1, capture.starts == 1, capture.pauses == 0,
                          model.panelCapturePresentation.state == .standby else {
                        throw ReviewFailure("background final changed capture or produced a second transcript")
                    }
                    let second = try await model.store.createRecording()
                    let secondTicket = try await model.store.beginFusionRecognition(recordingID: second.id)
                    let reviewer = ModelConfiguration(purpose: .textFusion, provider: .openAIResponses, model: "synthetic-review")
                    let review = try await model.store.beginModelRun(ticket: secondTicket, configuration: reviewer)
                    capture.state = .speaking; capture.level = 0.7; model.objectWillChange.send()
                    try await model.store.finishRecognition(ticket: firstTicket)
                    await model.refresh()
                    guard model.panelCapturePresentation.liveVoiceLevel != nil, capture.starts == 1, capture.pauses == 0 else {
                        throw ReviewFailure("late first-segment completion reset new speech")
                    }
                    try await self.inspectCapture("暂停收音", state: "正在识别", hasText: true, in: host)
                    try self.captureReview(host, name: "panel-capture-next-speech", output: output)
                    try await model.store.finishRecording(id: second.id)
                    capture.state = .listening; capture.level = 0; model.objectWillChange.send()
                    let phases = try await model.store.activeRecognitionPhases(recordingIDs: [second.id])
                    guard phases[second.id] == .textFusion, model.panelCapturePresentation.state == .standby,
                          model.panelCapturePresentation.liveVoiceLevel == nil else {
                        throw ReviewFailure("pending text fusion occupied the voice capsule after VAD end")
                    }
                    try await self.inspectCapture("暂停收音", state: "待命", hasText: true, in: host)
                    try self.captureReview(host, name: "panel-capture-fusion-pending", output: output)
                    capture.state = .speaking; capture.level = 0.5; model.objectWillChange.send()
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.pauses == 1 && capture.state == .paused }
                    try await model.store.finishModelRun(review, error: "合成复核结束", retryable: true)
                    try await model.store.failRecognition(ticket: secondTicket, message: "合成复核失败")
                    await model.refresh()
                    guard capture.starts == 1, capture.pauses == 1, model.panelCapturePresentation.state == .paused,
                          model.panelCapturePresentation.symbolName == "play.fill",
                          model.recent.first(where: { $0.id == first.id })?.text == final else {
                        throw ReviewFailure("late review callback restarted paused capture or changed prior final text")
                    }
                    try await self.inspectCapture("继续收音", state: "暂停", hasText: true, in: host)
                    try self.captureReview(host, name: "panel-capture-paused", output: output)
                    print("UI_VAD_END_PASS running ASR/fusion permit standby; late final updates one transcript; old callbacks preserve new speech and manual pause")
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.starts == 2 && capture.state == .listening && model.panelCapturePresentation.state == .standby }
                    try await self.inspectCapture("暂停收音", state: "待命", hasText: true, in: host)
                    guard model.captureActionLabel == "暂停收音" else { throw ReviewFailure("resuming capture did not restore the pause action") }
                    print("UI_NATIVE_CAPTURE_ACK paused_to_listening starts=2; actual capture button, injected microphone boundary")
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.pauses == 2 && capture.state == .paused }
                    capture.state = .starting; model.objectWillChange.send()
                    try await Task.sleep(for: .milliseconds(100))
                    try await self.inspectCapture("取消开启", state: "正在准备", hasText: true, in: host)
                    try self.captureReview(host, name: "panel-capture-starting", output: output)
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.pauses == 3 && capture.state == .paused }
                    capture.state = .interrupted("合成设备暂不可用，原音与文字仍保留。")
                    model.objectWillChange.send()
                    try await Task.sleep(for: .milliseconds(100))
                    try await self.inspectCapture("恢复收音", state: "需要恢复，合成设备暂不可用，原音与文字仍保留。", hasText: true, in: host)
                    try self.captureReview(host, name: "panel-capture-interrupted", output: output)
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.starts == 3 && capture.state == .listening }
                    try await self.press("panel.capture", in: host)
                    try await self.reviewUntil { capture.pauses == 4 && capture.state == .paused }
                    guard model.audio.state == .paused else { throw ReviewFailure("fixture capture reached the actual audio controller") }
                    print("UI_CONTROL_PASS bottom-right voice capsule handles start, speech, VAD end, pause, resume, cancel and recovery with an injected audio boundary")
                }
            } else {
                // Render the real SwiftUI view in CI without AX permission. Only
                // the capture boundary is synthetic; no physical click is claimed.
                model.toggleCapture()
                try await reviewUntil { capture.starts == 1 && capture.state == .listening }
                try await reviewValidatedWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240),
                    name: "panel-capture-listening", output: output, validation: { _ in
                    guard model.panelCapturePresentation.state == .standby,
                          model.panelCapturePresentation.symbolName == "circle.fill" else {
                        throw ReviewFailure("synthetic listening did not produce standby")
                    }
                })
                let current = try await model.store.createRecording()
                _ = try await model.store.saveEdit(recordingID: current.id, text: "我想让文字自然出现。说完这一句，它会安静地等我继续开口。")
                capture.state = .speaking; capture.level = 0.35
                await model.refresh(); model.objectWillChange.send()
                try await reviewValidatedWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240),
                    name: "panel-capture-speaking", output: output, validation: { _ in
                    guard model.panelCapturePresentation.state == .recognizing,
                          model.panelCapturePresentation.liveVoiceLevel != nil else {
                        throw ReviewFailure("synthetic speech lost its explicitly injected level")
                    }
                })
                try await model.store.finishRecording(id: current.id)
                let ticket = try await model.store.beginFusionRecognition(recordingID: current.id)
                let reviewer = ModelConfiguration(purpose: .textFusion, provider: .openAIResponses, model: "synthetic-review")
                let review = try await model.store.beginModelRun(ticket: ticket, configuration: reviewer)
                capture.state = .listening; capture.level = 0
                await model.refresh(); model.objectWillChange.send()
                try await reviewValidatedWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240),
                    name: "panel-capture-review", output: output, validation: { _ in
                    let phases = try await model.store.activeRecognitionPhases(recordingIDs: [current.id])
                    guard model.panelCapturePresentation.state == .standby,
                          model.panelCapturePresentation.liveVoiceLevel == nil, phases[current.id] == .textFusion else {
                        throw ReviewFailure("synthetic VAD end must show standby before background review finishes")
                    }
                })
                try await model.store.finishModelRun(review)
                try await model.store.finishRecognition(ticket: ticket)
                await model.refresh()
                try await reviewValidatedWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240),
                    name: "panel-capture-returned-standby", output: output, validation: { _ in
                    guard model.panelCapturePresentation.state == .standby, capture.state == .listening,
                          capture.starts == 1, capture.pauses == 0,
                          model.recent.first(where: { $0.id == current.id })?.text == "我想让文字自然出现。说完这一句，它会安静地等我继续开口。" else {
                        throw ReviewFailure("synthetic finalization changed capture or the retained user text")
                    }
                })
                model.toggleCapture()
                try await reviewUntil { capture.pauses == 1 && capture.state == .paused }
                try await reviewValidatedWindow(InputPanelView(model: model), size: CGSize(width: 340, height: 240),
                    name: "panel-capture-paused", output: output, validation: { _ in
                    guard model.panelCapturePresentation.state == .paused,
                          model.panelCapturePresentation.symbolName == "play.fill",
                          model.audio.state == .paused else {
                        throw ReviewFailure("synthetic pause must retain the play icon without opening actual audio")
                    }
                })
                print("UI_SYNTHETIC_CAPTURE_STATES_PASS paused, standby, speech, standby during review and retained final text; injected capture, no AX control actions or microphone")
            }
            // The long-text Unicode fixture needs exactly one utterance. Clear is
            // now visual only; remove only these disposable fixture records.
            for row in model.records { try await model.store.deleteRecord(recordingID: row.id) }
            model.clearPanel(); model.notice = nil
            let text = (0..<70).map { "第\($0 + 1)行：保留完整表达和原有否定词，不要支付15元。Swift API cafe\u{301} 😀。" }.joined(separator: "\n")
            let row = try await model.store.createRecording()
            _ = try await model.store.saveEdit(recordingID: row.id, text: text)
            try await model.store.finishRecording(id: row.id); await model.refresh()
            var archives = 0, settings = 0, hides = 0
            model.openArchive = { archives += 1 }; model.openSettings = { settings += 1 }; model.hidePanel = { hides += 1 }
            try await reviewValidatedWindow(InputPanelView(model: model), size: CGSize(width: 360, height: 480),
                name: "panel-long-text", output: output, validation: { host in
                let scroll = try self.compactTranscript(in: host)
                @MainActor func bodyText() -> String {
                    guard let range = scroll.rendered.spans.first(where: { $0.entry.id == row.id })?.range else { return "" }
                    return (scroll.transcriptView.string as NSString).substring(with: range)
                }
                try await self.reviewUntil { bodyText().utf16.elementsEqual(text.utf16) }
                guard !scroll.transcriptView.isEditable, scroll.transcriptView.isSelectable else { throw ReviewFailure("transcript selection contract changed") }
                let composed = text.precomposedStringWithCanonicalMapping
                guard composed == text, composed.utf16.count != text.utf16.count else { throw ReviewFailure("Unicode fixture did not differ in UTF-16 representation") }
                for replacement in [composed, text] {
                    _ = try await model.store.saveEdit(recordingID: row.id, text: replacement); await model.refresh()
                    try await self.reviewUntil { bodyText().utf16.elementsEqual(replacement.utf16) }
                    guard bodyText().utf16.count == replacement.utf16.count else { throw ReviewFailure("native Unicode replacement retained stale UTF-16 length") }
                }
                print("UI_NATIVE_UNICODE_PASS Store-driven NFD to NFC to NFD preserves exact UTF-16 text and length")
                scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
                let selected = (text as NSString).range(of: "cafe\u{301} 😀", options: .literal)
                guard selected.location != NSNotFound else { throw ReviewFailure("exact NFD/emoji selection fixture unavailable") }
                scroll.transcriptView.setSelectedRange(selected)
                let origin = scroll.contentView.bounds.origin
                let incoming = (text as NSString).replacingCharacters(in: selected, with: "café 修订😄")
                let updated = incoming.replacingOccurrences(of: "第1行：保留完整表达", with: "第1行：更新后仍保留完整表达😀")
                    + "\n新增表达：否定、数字和术语必须保持完整。"
                _ = try await model.store.saveEdit(recordingID: row.id, text: updated); await model.refresh()
                try await self.reviewUntil { scroll.latestText.hasSuffix(updated) }
                guard scroll.hasDeferredUpdate, bodyText() == text,
                      scroll.transcriptView.selectedRange() == selected,
                      abs(scroll.contentView.bounds.origin.y - origin.y) < 1 else {
                    throw ReviewFailure("live revision replaced selected text or stole its viewport")
                }
                try self.captureReview(host, name: "panel-selection-held", output: output)
                if hasControls {
                    let expected = (text as NSString).substring(with: selected)
                    try await self.checkPrivateCopy(expected, board: copyBoard, capture: capture, model: model, host: host)
                    guard scroll.transcriptView.selectedRange() == selected, scroll.hasDeferredUpdate else {
                        throw ReviewFailure("copy released the held visible NFD/emoji selection")
                    }
                    print("UI_PRIVATE_COPY_PASS exact selected NFD/emoji copied to unique pasteboard; feedback settled; capture and held selection preserved")
                }
                if hasControls { try await self.selectMenu("latest", title: "回到最新", in: host) } else { scroll.jumpToLatest() }
                try await self.reviewUntil { bodyText() == updated && scroll.isFollowingLatest }
                guard scroll.transcriptView.selectedRange().length == 0,
                      scroll.documentVisibleRect.maxY >= scroll.transcriptView.bounds.maxY - 5 else { throw ReviewFailure("latest action did not apply pending text and reach the tail") }
                try self.captureReview(host, name: "panel-latest", output: output)
                if hasControls {
                    try await self.checkPrivateCopy(updated, board: copyBoard, capture: capture, model: model, host: host)
                    print("UI_PRIVATE_COPY_PASS current full text copied to unique pasteboard; feedback settled; capture preserved")
                }
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 120)); scroll.reflectScrolledClipView(scroll.contentView)
                try await self.reviewUntil { !scroll.isFollowingLatest }
                try await self.reviewUntil { !scroll.rendered.markers.isEmpty }
                let readingOrigin = scroll.contentView.bounds.origin
                let appended = updated + "\n用户上滚阅读时继续接收的新一句。"
                _ = try await model.store.saveEdit(recordingID: row.id, text: appended); await model.refresh()
                try await self.reviewUntil { bodyText() == appended }
                guard !scroll.isFollowingLatest, abs(scroll.contentView.bounds.origin.y - readingOrigin.y) < 1 else {
                    throw ReviewFailure("append stole the user's native scroll position")
                }
                guard let layout = scroll.transcriptView.layoutManager, let container = scroll.transcriptView.textContainer else {
                    throw ReviewFailure("native text layout unavailable")
                }
                let beforePoint = NSPoint(x: 0, y: scroll.documentVisibleRect.minY - scroll.transcriptView.textContainerInset.height)
                let beforeCharacter = layout.characterIndexForGlyph(at: layout.glyphIndex(for: beforePoint, in: container))
                let prefix = "新增的合成开头只调整上方排版，不应改变正在阅读的位置。\n"
                let prepended = prefix + appended
                _ = try await model.store.saveEdit(recordingID: row.id, text: prepended); await model.refresh()
                try await self.reviewUntil { bodyText() == prepended }
                let afterPoint = NSPoint(x: 0, y: scroll.documentVisibleRect.minY - scroll.transcriptView.textContainerInset.height)
                let afterCharacter = layout.characterIndexForGlyph(at: layout.glyphIndex(for: afterPoint, in: container))
                guard !scroll.isFollowingLatest, afterCharacter == beforeCharacter + prefix.utf16.count else {
                    throw ReviewFailure("earlier text revision changed the visible reading anchor")
                }
                if hasControls { try await self.selectMenu("latest", title: "回到最新", in: host) } else { scroll.jumpToLatest() }
                try await self.reviewUntil { scroll.isFollowingLatest }
                let nearBottom = NSPoint(x: 0, y: scroll.contentView.bounds.origin.y - 2)
                scroll.contentView.scroll(to: nearBottom); scroll.reflectScrolledClipView(scroll.contentView)
                try await self.reviewUntil { !scroll.isFollowingLatest }
                try await self.reviewUntil { !scroll.rendered.markers.isEmpty }
                let readingTail = scroll.contentView.bounds.origin.y
                let nearTailText = prepended + "\n近底上滚仍应保留阅读位置。"
                _ = try await model.store.saveEdit(recordingID: row.id, text: nearTailText); await model.refresh()
                try await self.reviewUntil { bodyText() == nearTailText }
                guard !scroll.isFollowingLatest, abs(scroll.contentView.bounds.origin.y - readingTail) < 0.001 else {
                    throw ReviewFailure("a two-point upward reading scroll silently resumed live following")
                }
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, scroll.transcriptView.bounds.height - scroll.contentSize.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await self.reviewUntil { scroll.isFollowingLatest }
                let resumedText = nearTailText + "\n主动回到底部后继续跟随。"
                _ = try await model.store.saveEdit(recordingID: row.id, text: resumedText); await model.refresh()
                try await self.reviewUntil { bodyText() == resumedText && scroll.isFollowingLatest }
                guard abs(scroll.documentVisibleRect.maxY - scroll.transcriptView.bounds.maxY) < 0.001 else {
                    throw ReviewFailure("explicitly returning to the actual bottom did not resume following new text")
                }
                print("UI_NATIVE_NEAR_BOTTOM_PASS two-point upward scroll retains position; explicitly reaching the bottom resumes following")
                print("UI_NATIVE_TEXT_PASS actual read-only NSTextView selection, Store-driven updates, manual scroll retention and explicit latest; no focus or key events")
                if hasControls { print("UI_CONTROL_PASS native context-menu latest resumes one continuous transcript after selection and scrolling") }
            }, interaction: { host in
                try await self.inspectCapture("继续收音", state: "暂停", hasText: true, in: host)
                try await self.selectMenu("edit", title: "在档案中编辑这段文字", in: host)
                try await self.reviewUntil { archives == 1 && model.selected?.id == row.id && !model.editorDraftLoading }
                guard model.editorDraft.contains("用户上滚阅读") else { throw ReviewFailure("contextual edit did not open the existing saved transcript editor") }
                print("UI_CONTROL_PASS contextual edit reaches existing archive editor with latest saved text; no second transcript or writeback path")
                model.closeDetail()
                try await self.selectMenu("archive", title: "语音档案…", in: host)
                try await self.reviewUntil { archives == 2 }
                try await self.selectMenu("settings", title: "设置…", in: host)
                try await self.reviewUntil { settings == 1 }
                try await self.selectMenu("hide", title: "收起输入板", in: host)
                try await self.reviewUntil { archives == 2 && settings == 1 && hides == 1 }
                guard archives == 2, settings == 1, hides == 1 else { throw ReviewFailure("Context menu navigation did not route to existing actions") }
                try await self.selectMenu("clear", title: "清空输入板（保留档案）", in: host)
                try await self.reviewUntil { model.recent.isEmpty }
                await model.refresh()
                guard model.recent.isEmpty, let saved = try await model.store.recording(id: row.id), saved.text.contains("用户上滚阅读") else {
                    throw ReviewFailure("Context menu clear removed archive content")
                }
                model.stageInPanel(DisplayRecording(source: saved), showPanel: false); await model.refresh()
                print("UI_CONTROL_PASS Transcript context menu archive/settings/hide/clear actions retain the saved text")
            })
            var opens = 0
            model.openPanel = { opens += 1 }
            let starts = capture.starts, pauses = capture.pauses, state = capture.state
            try await reviewWindow(VoiceEntryView(model: model, open: model.openPanel), size: CGSize(width: 42, height: 42),
                name: "voice-entry", output: output) { host in
                try await self.press("voiceEntry.open", in: host)
                try await self.reviewUntil { opens == 1 }
                guard capture.starts == starts, capture.pauses == pauses, capture.state == state else {
                    throw ReviewFailure("lightweight entry changed capture rather than only opening the transcript")
                }
                print("UI_CONTROL_PASS lightweight voice entry opens the transcript once without starting, pausing or changing capture")
            }
            try await reviewWindow(SettingsView(model: model), size: CGSize(width: 650, height: 840),
                name: "settings-floating-entry", output: output) { host in
                try await self.press("settings.page.input", in: host)
                try await Task.sleep(for: .milliseconds(120))
                guard !model.floatingEntryEnabled, !preferences.bool(forKey: "floatingEntryEnabled") else {
                    throw ReviewFailure("fresh isolated settings unexpectedly enabled the desktop entry")
                }
                try await self.press("settings.floatingEntry", in: host)
                // The diagnostic process keeps NSArgumentDomain false to prevent
                // any test from opening a desktop entry. Check the real saved
                // suite value beneath that intentional process-wide override.
                try await self.reviewUntil { model.floatingEntryEnabled && preferences.persistentDomain(forName: suite)?["floatingEntryEnabled"] as? Bool == true }
                try await self.press("settings.floatingEntry", in: host)
                try await self.reviewUntil { !model.floatingEntryEnabled && preferences.persistentDomain(forName: suite)?["floatingEntryEnabled"] as? Bool == false }
                guard capture.starts == starts, capture.pauses == pauses, capture.state == state else {
                    throw ReviewFailure("desktop entry setting changed capture")
                }
                print("UI_CONTROL_PASS native desktop-entry setting persists on/off only in isolated preferences and leaves capture unchanged")
            }
            await model.prepareForExit()
        } catch { await model.prepareForExit(); throw error }
    }

    @MainActor private func reviewFirstConnection(output: URL) async throws {
        let suite = "app.saytile.test.ui-connection." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-ui-connection-" + UUID().uuidString)
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let fixture = UIConnectionFixture()
        let model = try AppModel(directory: directory, preferences: preferences, connectionDependencies: fixture.dependencies)
        await model.initialLoad()
        model.recognitionConfiguration.languagePreference = .chinese
        do {
            guard model.records.isEmpty, fixture.saved.isEmpty, !model.connectionVerified,
                  !model.recognitionConfiguration.cloudEnabled else { throw ReviewFailure("first connection fixture was not empty") }
            try await reviewWindow(Form { RecognitionSettingsSection(model: model) }.formStyle(.grouped),
                size: CGSize(width: 650, height: 840), name: "connection-first-empty", output: output)
            if ProcessInfo.processInfo.environment["SAYTILE_UI_CONTROL_PROBE"] != nil {
                try await reviewWindow(Form { RecognitionSettingsSection(model: model) }.formStyle(.grouped),
                    size: CGSize(width: 650, height: 840), name: "connection-first-success", output: output) { host in
                    try await self.press("recognition.configureServices", in: host)
                    for item in model.recognitionConfiguration.activeModels {
                        let prefix = "recognition.model." + item.id.uuidString.lowercased()
                        try await self.press(prefix + ".header", in: host)
                        if item.provider == .qwenMessage { try await self.setValue("fixture-workspace", for: prefix + ".workspace", in: host) }
                        try await self.setValue(UIConnectionFixture.credential, for: prefix + ".secret", in: host, secure: true)
                        try await self.press(prefix + ".saveKey", in: host)
                        guard model.hasCredential(item) else { throw ReviewFailure("native save-key action failed") }
                        try await self.press(prefix + ".consent", in: host)
                        guard model.recognitionConfiguration.models.first(where: { $0.id == item.id })?.cloudConsent == true else {
                            throw ReviewFailure("native service consent did not update configuration")
                        }
                        try await self.press(prefix + ".header", in: host)
                    }
                    try await self.reviewUntil { !model.applyingRecognitionSettings }
                    guard fixture.saved.count == 2, !model.connectionCheckAuthorized, fixture.requests == 0,
                          model.recognitionConfiguration.models[0].workspaceID == "fixture-workspace" else {
                        throw ReviewFailure("first setup silently connected or did not save native fields")
                    }
                    try self.captureReview(host, name: "connection-first-ready", output: output)
                    print("UI_STATE_CAPTURE connection-first-ready after native secure fields/save/consent; no network")
                    try await self.press("connection.checkCosts", in: host)
                    try self.captureReview(host, name: "connection-first-costs", output: output)
                    print("UI_STATE_CAPTURE connection-first-costs after native disclosure action")
                    try await self.press("connection.checkCosts", in: host)
                    try await self.press("connection.authorizeCheck", in: host)
                    try await self.press("connection.startCheck", in: host)
                    try await self.reviewUntil { !model.checkingConnection && !model.applyingRecognitionSettings }
                    guard fixture.requests == 1, model.connectionVerified, model.appliedRecognitionConfiguration.cloudEnabled,
                          model.recognitionConfiguration.cloudEnabled else { throw ReviewFailure("native first connection did not pass the receipt-enable branch") }
                    print("UI_CONTROL_PASS first connection via native Workspace/two selected secure fields/save/consent/cost/start; TEST_ONLY injected receipt, no live verification")
                }
                fixture.outcome = .failure
                try await reviewWindow(Form { RecognitionSettingsSection(model: model, initiallyExpanded: true) }.formStyle(.grouped),
                    size: CGSize(width: 650, height: 840), name: "connection-first-failure", output: output) { host in
                    try await self.press("connection.authorizeCheck", in: host)
                    try await self.press("connection.startCheck", in: host)
                    try await self.reviewUntil { !model.checkingConnection }
                    guard fixture.requests == 2, !model.connectionVerified, !model.appliedRecognitionConfiguration.cloudEnabled,
                          model.connectionReport?.services.allSatisfy({ $0.state == .failed }) == true else { throw ReviewFailure("failed check did not keep local recognition") }
                    print("UI_CONTROL_PASS native retry displays isolated service failure and keeps cloud disabled")
                }
                fixture.outcome = .waitForCancellation
                try await reviewWindow(Form { RecognitionSettingsSection(model: model, initiallyExpanded: true) }.formStyle(.grouped),
                    size: CGSize(width: 650, height: 840), name: "connection-first-cancelled", output: output) { host in
                    try await self.press("connection.authorizeCheck", in: host)
                    try await self.press("connection.startCheck", in: host)
                    try await self.reviewUntil { model.connectionReport?.services.allSatisfy({ $0.state == .receiving }) == true }
                    try self.captureReview(host, name: "connection-first-progress", output: output)
                    print("UI_STATE_CAPTURE connection-first-progress from injected backend progress through actual AppModel")
                    try await self.press("connection.cancelCheck", in: host)
                    try await self.reviewUntil { !model.checkingConnection && fixture.active == 0 }
                    guard fixture.requests == 3, !model.connectionVerified, !model.appliedRecognitionConfiguration.cloudEnabled,
                          model.connectionReport?.services.allSatisfy({ $0.state == .cancelled }) == true else { throw ReviewFailure("native cancellation left stale connection cards") }
                    print("UI_CONTROL_PASS native cancel closes injected verification and settles all service cards")
                }
            }
            await model.prepareForExit()
        } catch { await model.prepareForExit(); throw error }
    }
}

/// Test windows cannot acquire keyboard focus, even when their owned field editor
/// is exercised programmatically. The consumer's actual VoicePanel is unchanged.
@MainActor private final class ReviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class UIPanelCaptureFixture {
    var state: CaptureState = .paused
    var level: Float = 0
    var starts = 0
    var pauses = 0
    var dependencies: AppCaptureDependencies {
        AppCaptureDependencies(state: { _ in self.state },
            start: { _ in self.starts += 1; self.state = .listening },
            pause: { _ in self.pauses += 1; self.state = .paused }, level: { _ in self.level })
    }
}

/// Same AppModel dependency seam as the controller probe; only the peer outcome is
/// injected. Never read Keychain, upload audio or instantiate a provider transport.
@MainActor private final class UIConnectionFixture {
    enum Outcome { case success, failure, waitForCancellation }
    static let credential = "simulator-fixture-credential"
    var saved = Set<UUID>()
    var requests = 0
    var active = 0
    var outcome: Outcome = .success
    var dependencies: AppConnectionDependencies {
        AppConnectionDependencies(presence: { self.saved.contains($0.id) ? .saved : .missing },
            save: { value, item in
                guard value == Self.credential else { throw ProviderFailure.authorization }
                self.saved.insert(item.id)
            }, delete: { self.saved.remove($0.id) }, verify: { configuration, progress in
                guard configuration.activeModels.allSatisfy({ self.saved.contains($0.id) && $0.cloudConsent }) else { throw ProviderFailure.authorization }
                self.requests += 1; self.active += 1; defer { self.active -= 1 }
                progress(try Self.report(configuration, state: .accountAccepted))
                try await Task.sleep(for: .milliseconds(150))
                progress(try Self.report(configuration, state: .receiving))
                if self.outcome == .waitForCancellation { try await Task.sleep(for: .seconds(30)); throw CancellationError() }
                try await Task.sleep(for: .milliseconds(150))
                return try Self.report(configuration, state: self.outcome == .success ? .verified : .failed)
            }, applyConfiguration: { _, _ in }, revokeCloud: { $0.revokeCloudRecognition() })
    }
    private static func report(_ configuration: RecognitionConfiguration, state: ConnectionServiceState) throws -> CloudConnectionReport {
        let success = state == .verified
        let rows: [[String: Any]] = configuration.activeModels.map {
            var value: [String: Any] = ["id": $0.id.uuidString, "provider": $0.provider.rawValue, "state": state.rawValue]
            if state == .failed { value["code"] = "quota_exhausted"; value["message"] = "测试情形：服务余额不足，请在服务商账户处理后重新检查。" }
            return value
        }
        let value: [String: Any] = ["configurationFingerprint": CloudConnectionVerifier.fingerprint(configuration), "date": 0,
            "live": success, "services": rows, "transcript": success ? "TEST_ONLY：不要支付15元，send the report。" : "",
            "pipelineCompleted": success, "elapsedSeconds": 0, "reviewRequests": 0,
            "message": "TEST_ONLY 原生交互替身；未连接真实服务。"]
        return try JSONDecoder().decode(CloudConnectionReport.self, from: JSONSerialization.data(withJSONObject: value))
    }
}

// Records process identity transitions only, never another app's UI or contents.
private final class ReviewActivations: @unchecked Sendable {
    private let lock = NSLock()
    private let ownPID: pid_t
    private var own = false
    private var others = 0
    init(ownPID: pid_t) { self.ownPID = ownPID }
    func record(pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        if pid == ownPID { own = true } else { others += 1 }
    }
    var candidateActivated: Bool { lock.lock(); defer { lock.unlock() }; return own }
    var otherActivations: Int { lock.lock(); defer { lock.unlock() }; return others }
}
