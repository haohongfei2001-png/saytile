import SaytileVoiceUI
import SwiftUI
import AppKit
import SaytileKit

struct InputPanelView: View {
    @ObservedObject var model: AppModel
    @ViewState private var followsLatest = true
    @StateObject private var access = PanelTranscriptAccess()
    @ViewState private var selectedText = ""
    @ViewState private var latestRequest = 0
    private var document: PanelTimelineDocument {
        PanelTimelineDocument(page: model.timeline, tail: model.timelineTail, idle: model.timelineIdle, reading: !followsLatest)
    }
    private var canCopy: Bool { model.timelineTail != nil || !selectedText.isEmpty }
    private var editTarget: DisplayRecording? {
        if let view = access.view {
            let selection = view.transcriptView.selectedRange()
            let character = selection.length > 0 ? selection.location : view.transcriptView.contextCharacter
            if let character, let match = view.rendered.spans.first(where: { NSLocationInRange(character, $0.range) }) {
                return DisplayRecording(source: match.entry.recording)
            }
        }
        return model.timelineTail.map { DisplayRecording(source: $0.recording) }
    }

    var body: some View {
        let presentation = model.panelCapturePresentation
        let capture = VoicePanelCapture(state: presentation.state, level: presentation.liveVoiceLevel,
            actionLabel: presentation.accessibilityLabel, accessibilityValue: presentation.accessibilityValue)
        VoiceSurfacePanel(document: document, access: access, capture: capture, canCopy: canCopy,
            selectedText: selectedText, onCopy: copyTranscript, onToggle: model.toggleCapture,
            onPage: { model.moveTimeline(older: $0) }, onSelectionChange: { selectedText = $0 },
            onFollowChange: { follows in
                if followsLatest != follows {
                    followsLatest = follows
                    if follows { model.followTimeline() } else { model.pinTimeline() }
                }
            }, focusPosition: model.timelineFocus, editing: model.archiveIsKey && model.selected != nil,
            latestRequest: latestRequest, fillContextMenu: fillContextMenu,
            target: model.directMode ? model.targetLabel : nil, notice: model.panelCaptureDetail ?? model.notice,
            placeholder: placeholder, placeholderDetail: model.completedFirstTranscript ? nil : firstUseDetail,
            menu: { panelActions })
    }

    private var placeholder: String? {
        guard model.timeline.entries.isEmpty || !model.completedFirstTranscript && model.timeline.entries.allSatisfy({ $0.recording.text.isEmpty }) else { return nil }
        return !model.completedFirstTranscript ? firstUseTitle : (model.isListening ? "开口，文字会出现在这里。" : nil)
    }

    private var firstUseTitle: String {
        switch model.panelCapturePresentation.state {
        case .starting: "正在准备收音…"
        case .standby, .recognizing: "说一句话试试。"
        case .recoveryNeeded: "收音已暂停"
        case .paused: "点右下角，开始说话。"
        }
    }
    private var firstUseDetail: String {
        if model.captureProblem {
            return model.microphoneDenied ? "点右下角打开麦克风设置。允许后，回来继续。" : "处理上方提示后，点右下角继续。"
        }
        if model.audio.preparingAppleSpeech { return "正在准备中文资源，已开始的录音会保留。" }
        if model.audio.appleResourceFailure != nil { return "中文资源尚未就绪。到设置中的本地模型重试，原音会保留。" }
        return model.isListening ? "点左下角复制文字，再点右侧暂停。" : "讲话时文字会出现在这里。左下角可复制。"
    }

    private func copyTranscript() {
        guard canCopy else { return }
        let view = access.view
        model.copyTimeline(selection: view?.selectionSnapshot ?? selectedText, displayed: view?.rendered.displayed ?? [:])
    }

    private func insertTranscript() {
        let document = access.view?.rendered
        model.insertFromPanel(rendered: document?.spans.map(\.entry) ?? [], displayed: document?.displayed ?? [:])
    }

    /// Both contextual surfaces expose the same commands and eligibility.
    /// The AppKit text view also supports the system Show Menu action.
    private struct PanelCommand: Identifiable {
        let id: String
        let title: String
        var enabled = true
        var checked = false
        var action: (@MainActor () -> Void)?
        var copyID: String {
            switch id {
            case "edit", "latest": "panel." + id
            case "dismiss": "panel.dismissNotice"
            default: "panel.more." + id
            }
        }
    }
    private var commandGroups: [[PanelCommand]] {
        var groups: [[PanelCommand]] = [
            [.init(id: "copy", title: selectedText.isEmpty ? "复制当前文字" : "复制所选文字", enabled: canCopy, action: { copyTranscript() }),
             .init(id: "edit", title: "在档案中编辑这段文字", enabled: editTarget != nil, action: { if let item = editTarget { model.select(item) } }),
             .init(id: "latest", title: "回到最新", enabled: !followsLatest, action: { model.followTimeline(); latestRequest += 1 })],
            [.init(id: "archive", title: "语音档案…", action: { model.openArchive() }),
             .init(id: "settings", title: "设置…", action: { model.openSettings() })],
            [.init(id: "free", title: "自由记录", checked: !model.directMode, action: { model.setDirect(false) }),
             .init(id: "direct", title: "直接输入", checked: model.directMode, action: { model.setDirect(true) }),
             .init(id: "bind", title: "绑定当前草稿", action: { model.bindTarget() }),
             .init(id: "insert", title: model.isInserting ? "正在插入…" : (model.insertionArchiveEntry == nil ? "插入最新时间组" : "插入档案定位的这段文字"),
                   enabled: !model.isInserting && model.hasPanelInsertionScope, action: insertTranscript)]
        ]
        var last: [PanelCommand] = []
        if model.captureProblem && model.microphoneDenied {
            last.append(.init(id: "microphone", title: "打开麦克风系统设置…", action: { model.openMicrophoneSettings() }))
        }
        last.append(.init(id: "save", title: model.saveLabel, enabled: false))
        last.append(.init(id: "clear", title: "清空输入板（保留档案）", enabled: !model.isInserting && model.hasPanelInsertionScope, action: { model.clearPanel(); latestRequest += 1 }))
        if model.notice != nil, model.panelCaptureDetail == nil {
            last.append(.init(id: "dismiss", title: "关闭提示", action: { model.notice = nil }))
        }
        last.append(.init(id: "hide", title: "收起输入板", action: { model.hidePanel() }))
        groups.append(last)
        return groups
    }

    @ViewBuilder private var panelActions: some View {
        let groups = commandGroups
        ForEach(groups.indices, id: \.self) { i in
            if i != 0 { Divider() }
            ForEach(groups[i]) { command in
                if let action = command.action {
                    Button(action: action) {
                        if command.checked { Label(command.title, systemImage: "checkmark") }
                        else { Text(command.title) }
                    }.disabled(!command.enabled).accessibilityIdentifier(command.copyID)
                } else { Text(command.title) }
            }
        }
    }
    private func fillContextMenu(_ menu: NSMenu) {
        for (i, commands) in commandGroups.enumerated() {
            if i != 0 { menu.addItem(.separator()) }
            for command in commands {
                let item: NSMenuItem
                if let action = command.action {
                    item = TranscriptMenuItem(title: command.title, identifier: "panel.menu." + command.id, action: action)
                } else {
                    item = NSMenuItem(title: command.title, action: nil, keyEquivalent: "")
                }
                item.isEnabled = command.enabled
                item.state = command.checked ? .on : .off
                menu.addItem(item)
            }
        }
    }

}

struct ArchiveView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searching: Bool
    private let filters: [(RecordingFilter, String, String)] = [(.transcribed, "全部文字", "text.alignleft"), (.pinned, "已收藏", "pin"), (.needsRecovery, "待恢复", "arrow.clockwise"), (.all, "全部记录", "tray.full")]
    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 920
            let rows = model.records
            HStack(spacing: 0) {
                if wide {
                    VStack(alignment: .leading, spacing: 3) {
                        WorkspaceBrand().padding(.leading, 9).padding(.vertical, 18).padding(.bottom, 7)
                        ForEach(filters, id: \.1) { filter, title, symbol in
                            WorkspaceNavRow(title: title, symbol: symbol, selected: model.recordFilter == filter) { model.recordFilter = filter }
                        }
                        Spacer()
                        WorkspaceNavRow(title: "设置与存储", symbol: "gearshape", selected: false, action: model.openStorageSettings)
                    }.padding(12).frame(width: 160).background(.regularMaterial)
                    Divider()
                }
                if wide || model.selected == nil {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text("语音档案").font(WorkspaceStyle.title).accessibilityAddTraits(.isHeader)
                            Spacer(); Button("回到输入板", action: model.openPanel)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("搜索文字、历史版本或草稿", text: $model.query).textFieldStyle(.plain)
                                .accessibilityLabel("搜索语音记录").focused($searching).onSubmit { Task { await model.refresh() } }
                            if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("清除搜索") }
                        }.padding(.horizontal, 10).frame(height: 32).background(WorkspaceStyle.editor, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary))
                        if !wide { Picker("显示", selection: $model.recordFilter) { ForEach(filters, id: \.1) { filter, title, _ in Text(title).tag(filter) } }.pickerStyle(.segmented).labelsHidden() }
                        if let notice = model.notice { Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                        if model.records.isEmpty {
                            ContentUnavailableView(model.query.isEmpty ? (model.recordFilter == .transcribed ? "还没有转写文字" : "这里暂时没有记录") : "没有匹配结果",
                                systemImage: model.query.isEmpty ? "tray" : "magnifyingglass",
                                description: Text(model.query.isEmpty ? (model.recordFilter == .transcribed ? "讲话转成文字后会按日期显示。未转写的原音可在“全部记录”中找到。" : "符合当前筛选的记录会显示在这里。") : "试试更短的关键词，或清除搜索。"))
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, item in
                                        if offset == 0 || !Calendar.current.isDate(rows[offset-1].date, inSameDayAs: item.date) {
                                            Text(item.date, format: .dateTime.year().month().day()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                                .padding(.top, 13).padding(.bottom, 7).accessibilityAddTraits(.isHeader)
                                        }
                                        ArchiveRow(item: item, model: model)
                                        Divider()
                                    }
                                    if model.hasMore { Button("加载更早记录", action: model.loadMore).padding(.vertical, 12) }
                                }
                            }
                        }
                    }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if let selected = model.selected {
                    if wide { Divider() }
                    RecordDetailView(item: selected, model: model).frame(maxWidth: wide ? min(360, geo.size.width * 0.33) : .infinity)
                        .background(WorkspaceStyle.editor.opacity(0.55))
                }
            }.background(WorkspaceStyle.background)
        }.foregroundStyle(WorkspaceStyle.foreground).tint(WorkspaceStyle.accent)
            .background(Button("") { if model.selected != nil { model.closeDetail() }; searching = true }.keyboardShortcut("f").hidden().accessibilityHidden(true))
    }
}

private struct ArchiveRow: View {
    let item: DisplayRecording
    @ObservedObject var model: AppModel
    var body: some View {
        let hasText = !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Text(item.date, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
                    .accessibilityIdentifier("archive.time.\(item.id)")
                if item.pinned { Image(systemName: "pin.fill").accessibilityLabel("已收藏") }
                if item.hasAudio {
                    Button { model.play(item) } label: {
                        Label {
                            Text(model.playingID == item.id ? "停止" : "回听 · \(max(1, Int(item.source.duration.rounded()))) 秒")
                        } icon: {
                            Image(systemName: model.playingID == item.id ? "stop.fill" : "play.fill")
                        }
                    }
                    .accessibilityLabel(model.playingID == item.id ? "停止回听" : "回听原音")
                    .accessibilityIdentifier("archive.play.\(item.id)")
                    .help(item.audioLabel)
                }
                Spacer()
                if hasText {
                    Button { model.copy(item.text) } label: { Image(systemName: "doc.on.doc") }
                        .accessibilityLabel("复制这段文字").accessibilityIdentifier("archive.copy.\(item.id)").help("复制这段文字")
                }
                Button { Task { await model.selectForEditing(item) } } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("查看和编辑这段表达").accessibilityIdentifier("archive.detail.\(item.id)").help("查看和编辑这段表达")
            }.buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            if !hasText {
                Text(item.emptyTextLabel).foregroundStyle(.secondary)
            } else {
                Text(verbatim: item.text)
                    .font(.system(size: 16)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("archive.text.\(item.id)")
            }
            if !model.query.isEmpty && !item.text.localizedCaseInsensitiveContains(model.query) {
                Text("匹配历史版本或草稿").font(.caption).foregroundStyle(.secondary)
            }
            if let label = model.insertionLabels[item.id] { Label(label, systemImage: "arrow.up.forward.app").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 11).padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.selected?.id == item.id ? WorkspaceStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct RecordDetailView: View {
    let item: DisplayRecording
    @ObservedObject var model: AppModel
    @ViewState private var showVersions = false
    @ViewState private var deletingAudio = false
    @ViewState private var deletingRecord = false
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("这段表达").font(.system(size: 16, weight: .semibold)); Spacer()
                Button { model.closeDetail() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("返回记录列表").keyboardShortcut(.cancelAction)
            }
            Text(item.date, format: .dateTime.year().month().day().hour().minute().second()).font(.system(size: 11)).foregroundStyle(.secondary)
            if !item.hasAudio { Text(item.audioLabel).font(.caption).foregroundStyle(.secondary) }
            if let error = item.source.displayedError {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.amber).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            TextEditor(text: Binding(get: { model.editorDraft }, set: { newText in model.updateEditorDraft(newText) })).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(8).background(WorkspaceStyle.editor, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).frame(minHeight: 135, idealHeight: 180).accessibilityLabel("编辑这段文字").disabled(!model.editorCanEdit)
            Text(model.editorDraftStatus).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                Button(model.savingEditorChanges ? "正在保存…" : "保存修改") { Task { await model.saveEditorChanges() } }.keyboardShortcut("s").buttonStyle(QuietButton(prominent: true)).disabled(!model.editorCanEdit || model.savingEditorChanges || model.editorDraft == item.text)
                Button { model.pin(item) } label: { Image(systemName: item.pinned ? "pin.slash" : "pin") }.buttonStyle(QuietButton()).accessibilityLabel(item.pinned ? "取消收藏" : "收藏这段表达")
            }
            if model.playingID == item.id {
                VStack(spacing: 6) {
                    Slider(value: Binding(get: { model.audio.playbackPosition }, set: { model.audio.seekPlayback(to: $0) }), in: 0...max(0.1, model.audio.playbackDuration))
                        .accessibilityLabel("原音播放进度")
                    HStack {
                        Text(playbackTime(model.audio.playbackPosition)); Spacer(); Text(playbackTime(model.audio.playbackDuration))
                    }.font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(model.playingID == item.id ? "停止" : "回听") { model.play(item) }.disabled(!item.hasAudio)
                Button(!model.deviceOnly && !model.hosted.selected && model.appliedRecognitionConfiguration.cloudEnabled ? "用云端重新识别" : "本机重新识别") { model.retry(item) }
                    .help(!model.deviceOnly && !model.hosted.selected && model.appliedRecognitionConfiguration.cloudEnabled ? "仅将这段原音交给当前已授权的服务重新识别" : "仅在这台 Mac 上处理这段原音")
                    .disabled(!item.hasAudio || item.isRecording)
                Button("复制") { model.copy(model.editorDraft) }
            }.buttonStyle(QuietButton())
            HStack {
                Button("带到输入板") { model.stageInPanel(item) }.disabled(item.text.isEmpty || model.editorDraft != item.text).help("先保存修改，再将这段表达带到输入板")
            }.buttonStyle(QuietButton())
            Divider()
            DisclosureGroup("文字版本（\(model.versions.count)）", isExpanded: $showVersions) {
                ForEach(model.versions) { version in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(version.label).font(.caption).foregroundStyle(.secondary)
                        Text(version.text).font(.callout).textSelection(.enabled)
                        Button("复制此版本") { model.copy(version.text) }.buttonStyle(.link)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
            }
            Divider()
            Button("仅删除原音…") { deletingAudio = true }.disabled(item.source.audioState == .deleted || item.source.audioState == .deletePending || item.isRecording)
            Button("删除整条记录…", role: .destructive) { deletingRecord = true }.disabled(item.isRecording)
        }.padding(22)
        }
            .task(id: item.id) { showVersions = false; await model.prepareEditorIfNeeded(item) }
            .onDisappear { Task { _ = await model.flushEditorDrafts() } }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                Task { _ = await model.flushEditorDrafts() }
            }
            .confirmationDialog("仅删除原音？文字和全部修改稿仍会保留。", isPresented: $deletingAudio, titleVisibility: .visible) {
                Button("删除原音，保留文字", role: .destructive) { model.eraseAudio(item) }
            }
            .confirmationDialog("删除这条记录的文字和原音？此操作无法撤销。", isPresented: $deletingRecord, titleVisibility: .visible) {
                Button("删除整条记录", role: .destructive) { model.deleteRecord(item) }
            }
    }
    private func playbackTime(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

