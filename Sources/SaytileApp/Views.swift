import SwiftUI
import AppKit

struct InputPanelView: View {
    @ObservedObject var model: AppModel
    @ViewState private var followsLatest = true
    @ViewState private var selectedText = ""
    @ViewState private var latestRequest = 0
    @ViewState private var captureHovered = false
    @FocusState private var captureFocused: Bool

    private var transcript: String { model.recent.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n") }
    private var canCopy: Bool { !transcript.isEmpty || !selectedText.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if model.directMode {
                Label(model.targetLabel, systemImage: "arrow.up.forward.app")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.bottom, 5)
                    .help(model.targetLabel).accessibilityIdentifier("panel.target")
            }
            if let message = model.panelCaptureDetail ?? model.notice {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(message).lineLimit(2).fixedSize(horizontal: false, vertical: true).help(message)
                    Spacer(minLength: 0)
                }.font(.system(size: 11)).foregroundStyle(Palette.amber)
                    .padding(.horizontal, 14).padding(.vertical, 5).accessibilityIdentifier("panel.notice")
            }

            CompactTranscriptView(text: transcript, latestRequest: latestRequest,
                onFollowChange: { followsLatest = $0 }, onSelectionChange: { selectedText = $0 },
                fillContextMenu: fillContextMenu)
                .overlay(alignment: .topLeading) {
                    if transcript.isEmpty {
                        Text(model.isListening ? "开口，文字会出现在这里。" : "从一句话开始。")
                            .font(.system(size: 16)).foregroundStyle(Palette.muted.opacity(0.8))
                            .padding(.top, 6).padding(.horizontal, 2).allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button(action: copyTranscript) {
                    Image(systemName: "doc.on.doc").font(.system(size: 12))
                        .frame(width: 34, height: 30).contentShape(Rectangle())
                        .foregroundStyle(Palette.accent.opacity(canCopy ? 1 : 0.5))
                        .background(.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.45), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                // Keep the menu host enabled for an empty panel. The copy action
                // itself is a no-op without text; archive/settings remain reachable.
                .contextMenu { panelActions }
                .help(canCopy ? "复制文字；右键打开编辑与更多操作" : "右键打开档案、设置与更多操作")
                .accessibilityLabel(selectedText.isEmpty ? "复制当前文字" : "复制所选文字")
                .accessibilityHint("右键或打开上下文菜单可编辑、回到最新、查看档案和设置")
                .accessibilityIdentifier("panel.copy")
                Spacer(minLength: 8)
                captureControl
            }
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 10)
        }
        .padding(.top, 10)
        .background(Palette.paper.opacity(0.82))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 0.75))
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyTranscript() {
        guard canCopy else { return }
        if selectedText.isEmpty { model.copyRecent() } else { model.copy(selectedText) }
    }

    private var captureControl: some View {
        let presentation = model.panelCapturePresentation
        return Button(action: model.toggleCapture) {
            Group {
                if let level = presentation.liveVoiceLevel {
                    // Only the current capture session's measured voice activity
                    // drives the meter; a pending transcript never fabricates it.
                    HStack(spacing: 2.5) {
                        ForEach(0..<5) { index in
                            Capsule().frame(width: 2.5, height: 4 + 11 * min(1, max(0, level)) * [0.4, 0.75, 1, 0.6, 0.35][index])
                        }
                    }.frame(width: 24, height: 18)
                } else {
                    Image(systemName: presentation.symbolName).font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 18)
                }
            }
            .foregroundStyle(model.captureProblem ? Palette.amber : Palette.accent)
            .frame(width: 78, height: 30)
            .background(Palette.accent.opacity(model.isListening ? 0.12 : 0.06), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 0.75))
            .contentShape(Capsule())
        }.buttonStyle(CaptureButtonStyle())
            .overlay(Capsule().stroke(Palette.accent.opacity(captureFocused ? 0.65 : captureHovered ? 0.24 : 0), lineWidth: captureFocused ? 2 : 1))
            .onHover { captureHovered = $0 }.focused($captureFocused)
            .help(presentation.accessibilityLabel)
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityValue(presentation.accessibilityValue)
            .accessibilityIdentifier("panel.capture")
    }

    private struct CaptureButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.62 : 1)
        }
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
             .init(id: "edit", title: "在档案中编辑最近一段", enabled: model.recent.last != nil, action: { if let item = model.recent.last { model.select(item) } }),
             .init(id: "latest", title: "回到最新", enabled: !followsLatest, action: { latestRequest += 1 })],
            [.init(id: "archive", title: "语音档案…", action: { model.openArchive() }),
             .init(id: "settings", title: "设置…", action: { model.openSettings() })],
            [.init(id: "free", title: "自由记录", checked: !model.directMode, action: { model.setDirect(false) }),
             .init(id: "direct", title: "直接输入", checked: model.directMode, action: { model.setDirect(true) }),
             .init(id: "bind", title: "绑定当前草稿", action: { model.bindTarget() }),
             .init(id: "insert", title: model.isInserting ? "正在插入…" : "插入当前文字", enabled: !model.isInserting && !transcript.isEmpty, action: { model.insertRecent() })]
        ]
        var last: [PanelCommand] = []
        if model.panelHasMore {
            last.append(.init(id: "earlier", title: model.loadingPanel ? "正在载入…" : "载入更早表达（已载入 \(model.recent.count) / \(model.panelCount) 段）", enabled: !model.loadingPanel, action: { model.loadEarlierPanel() }))
        }
        last.append(.init(id: "save", title: model.saveLabel, enabled: false))
        last.append(.init(id: "clear", title: "清空输入板（保留档案）", enabled: !model.isInserting && !model.recent.isEmpty, action: { model.clearPanel(); latestRequest += 1 }))
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

struct TranscriptCard: View {
    let item: DisplayRecording
    @ObservedObject var model: AppModel
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.date, format: .dateTime.hour().minute()).font(.system(size: 10, weight: .medium)).monospacedDigit()
                if item.pinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
                Spacer()
                Text(item.stateLabel).font(.system(size: 10))
            }.foregroundStyle(Palette.muted)
            Text(item.text.isEmpty ? item.emptyTextLabel : item.text)
                .font(.system(size: compact ? 14 : 15)).lineSpacing(6).textSelection(.enabled)
                .foregroundStyle(item.text.isEmpty ? Palette.muted : Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
            if let inputLabel = model.insertionLabels[item.id] {
                Label(inputLabel, systemImage: "arrow.up.forward.app").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !compact, !model.query.isEmpty, !item.text.localizedCaseInsensitiveContains(model.query) {
                Text("匹配到已保存的文字").font(.system(size: 10)).foregroundStyle(Palette.accent)
            }
            HStack(spacing: 14) {
                Label(item.audioLabel, systemImage: item.hasAudio ? "waveform" : "text.alignleft").font(.system(size: 10))
                Spacer()
                Button { model.play(item) } label: { Image(systemName: model.playingID == item.id ? "stop.fill" : "play.fill") }.disabled(!item.hasAudio).help("回听原音").accessibilityLabel(model.playingID == item.id ? "停止回听" : "回听原音")
                Button { model.copy(item.text) } label: { Image(systemName: "doc.on.doc") }.disabled(item.text.isEmpty).help("复制文字").accessibilityLabel("复制这段文字")
                Button { model.select(item) } label: { Image(systemName: "ellipsis") }.help("查看、修改及更多操作").accessibilityLabel("查看和编辑这段表达")
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(14).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.accent.opacity(0.09)))
    }
}

struct ArchiveView: View {
    @ObservedObject var model: AppModel
        var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) { VoiceMark(); Text("Saytile").font(.system(size: 20, weight: .semibold)) }.padding(.top, 12)
                VStack(spacing: 6) {
                    ForEach([("全部记录", "tray.full"), ("已收藏", "pin"), ("待恢复", "arrow.clockwise")], id: \.0) { name, icon in
                        Button { model.recordFilter = name == "已收藏" ? .pinned : name == "待恢复" ? .needsRecovery : .all } label: {
                            Label(name, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(11)
                                .background((name == "全部记录" && model.recordFilter == .all || name == "已收藏" && model.recordFilter == .pinned || name == "待恢复" && model.recordFilter == .needsRecovery) ? Palette.soft : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Text("每一次表达，\n都值得被留下。").font(.system(size: 12)).lineSpacing(7).foregroundStyle(Palette.muted)
                Divider()
                Button(action: model.openSettings) { Label("设置与存储", systemImage: "slider.horizontal.3") }.buttonStyle(.plain)
            }.padding(22).frame(width: 200).background(Palette.canvas.opacity(0.6))
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("语音档案").font(.system(size: 25, weight: .semibold))
                        Text("找回思路，接着表达。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button("回到此刻", action: model.openPanel).buttonStyle(QuietButton())
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("搜索语音记录", text: $model.query).textFieldStyle(.plain)
                    if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 9))
                if let notice = model.notice { Text(notice).font(.system(size: 12)).foregroundStyle(Palette.amber) }
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.records) { item in
                            TranscriptCard(item: item, model: model)
                        }
                        if model.records.isEmpty {
                            ContentUnavailableView(model.query.isEmpty ? (model.recordFilter == .all ? "还没有记录" : "这里暂时没有记录") : "没有匹配结果", systemImage: model.query.isEmpty ? "waveform" : "magnifyingglass", description: Text(model.query.isEmpty ? "开启自由记录，表达会自动保留在这里。" : "换一个搜索词试试。当前文字、历史版本和编辑草稿都会参与搜索。"))
                        }
                        if model.hasMore { Button("加载更早记录", action: model.loadMore).buttonStyle(QuietButton()) }
                    }
                }
            }.padding(30).frame(minWidth: 380)
            if let selected = model.selected {
                Divider()
                RecordDetailView(item: selected, model: model).frame(width: 310)
            }
        }.foregroundStyle(Palette.ink).background(Palette.paper).frame(minWidth: model.selected == nil ? 760 : 1040, minHeight: 570)
    }
}

struct RecordDetailView: View {
    let item: DisplayRecording
    @ObservedObject var model: AppModel
    @ViewState private var deletingAudio = false
    @ViewState private var deletingRecord = false
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("这段表达").font(.system(size: 16, weight: .semibold)); Spacer()
                Button { model.closeDetail() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            Text(item.date, format: .dateTime.year().month().day().hour().minute()).font(.system(size: 11)).foregroundStyle(Palette.muted)
            if let error = item.source.lastError {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.amber).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            TextEditor(text: Binding(get: { model.editorDraft }, set: { newText in model.updateEditorDraft(newText) })).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 9)).frame(height: 180).disabled(!model.editorCanEdit)
            Text(model.editorDraftStatus).font(.system(size: 10)).foregroundStyle(Palette.muted)
            HStack {
                Button(model.savingEditorChanges ? "正在保存…" : "保存修改") { Task { await model.saveEditorChanges() } }.buttonStyle(QuietButton(prominent: true)).disabled(!model.editorCanEdit || model.savingEditorChanges || model.editorDraft == item.text)
                Button { model.pin(item) } label: { Image(systemName: item.pinned ? "pin.slash" : "pin") }.buttonStyle(QuietButton())
            }
            if model.playingID == item.id {
                VStack(spacing: 6) {
                    Slider(value: Binding(get: { model.audio.playbackPosition }, set: { model.audio.seekPlayback(to: $0) }), in: 0...max(0.1, model.audio.playbackDuration))
                        .accessibilityLabel("原音播放进度")
                    HStack {
                        Text(playbackTime(model.audio.playbackPosition)); Spacer(); Text(playbackTime(model.audio.playbackDuration))
                    }.font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.muted)
                }
            }
            HStack {
                Button(model.playingID == item.id ? "停止" : "回听") { model.play(item) }.disabled(!item.hasAudio)
                Button(model.appliedRecognitionConfiguration.cloudEnabled ? "用云端重新识别" : "本机重新识别") { model.retry(item) }
                    .help(model.appliedRecognitionConfiguration.cloudEnabled ? "仅将这段原音交给当前已授权的服务重新识别" : "仅在这台 Mac 上处理这段原音")
                    .disabled(!item.hasAudio || item.isRecording)
                Button("复制") { model.copy(model.editorDraft) }
            }.buttonStyle(QuietButton())
            HStack {
                Button("带到输入板") { model.stageInPanel(item) }.disabled(item.text.isEmpty || model.editorDraft != item.text).help("先保存修改，再将这段表达带到输入板")
            }.buttonStyle(QuietButton())
            Divider()
            Spacer(minLength: 0)
            Button("仅删除原音…") { deletingAudio = true }.disabled(item.source.audioState == .deleted || item.source.audioState == .deletePending || item.isRecording)
            Button("删除整条记录…", role: .destructive) { deletingRecord = true }.disabled(item.isRecording)
        }.padding(22)
        }
            .task(id: item.id) { await model.prepareEditorIfNeeded(item) }
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

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ViewState private var cleanup = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { VoiceMark(size: 30); VStack(alignment: .leading) { Text("Saytile").font(.system(size: 23, weight: .semibold)); Text("自然开口，随时取用。 · " + (Bundle.main.object(forInfoDictionaryKey: "SaytileReleaseVersion") as? String ?? "V1 开发版本")).font(.system(size: 11)).foregroundStyle(Palette.muted) } }
            if let notice = model.notice { Text(notice).font(.system(size: 12)).foregroundStyle(Palette.amber).textSelection(.enabled) }
            Form {
                RecognitionSettingsSection(model: model)
                Section("收音与识别") {
                    LabeledContent("当前状态", value: model.captureLabel)
                    if let detail = model.panelCaptureDetail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.captureDetail")
                    }
                    Picker("输入设备", selection: $model.deviceID) { ForEach(model.devices) { device in Text(device.name).tag(device.id) } }
                    Text("开启后持续接收讲话；关闭输入板不会停止收音。设备断开、休眠和用户会话切换会明确暂停。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    LabeledContent("识别语言", value: model.appliedRecognitionConfiguration.cloudEnabled ? "中文 / English · 自动处理混说" : "普通话 · 本机备用")
                    LabeledContent("识别引擎", value: model.engineLabel)
                    Button("准备中文识别资源", action: model.prepareSpeech)
                    Button(model.captureActionLabel, action: model.toggleCapture)
                }
                Section("系统权限") {
                    LabeledContent("麦克风", value: model.microphoneLabel)
                    LabeledContent("辅助功能", value: model.accessibilityLabel)
                    Button("允许跨应用插入…", action: model.requestAccessibility)
                    Text("复制无需辅助功能权限。直接输入只追加到明确绑定的草稿，不会发送消息。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Section("原音与存储") {
                    LabeledContent("已用原音空间", value: model.storageLabel)
                    LabeledContent("保留策略", value: "保留至手动删除")
                    Text("达到 10 GB 时提醒。不会自动删除未识别、失败或收藏的原音。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Button(model.preparingCleanup ? "正在查找可清理原音…" : "预览清理 30 天前的已识别原音…") { Task { cleanup = await model.previewCleanup() } }.disabled(model.preparingCleanup)
                    Button("在 Finder 中显示资料目录", action: model.revealData)
                }
                Section("使用习惯") {
                    Toggle("登录时启动 Saytile", isOn: $model.launchAtLogin)
                    Toggle("在桌面右下角显示语音入口", isOn: $model.floatingEntryEnabled)
                        .accessibilityIdentifier("settings.floatingEntry")
                    Text("收起输入板时保留一个小入口；点击只展开文字，不会开启收音。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Picker("展开 / 收起输入板", selection: $model.shortcutChoice) {
                        Text("⌥ 空格").tag("option-space")
                        Text("⌃ ⌥ 空格").tag("control-option-space")
                        Text("⌘ ⇧ 空格").tag("command-shift-space")
                        Text("关闭快捷键").tag("disabled")
                    }
                    Text("快捷键注册失败时会显示提示，菜单栏仍然可用。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.formStyle(.grouped)
        }.padding(24).frame(minWidth: 560, idealWidth: 650, maxWidth: .infinity, minHeight: 570, idealHeight: 740, maxHeight: .infinity).background(Palette.paper).foregroundStyle(Palette.ink)
            .confirmationDialog("清理 \(model.cleanupCount) 条已识别、未收藏且超过 30 天的原音？已保存的文字会保留。", isPresented: $cleanup, titleVisibility: .visible) {
                Button("清理这些原音", role: .destructive, action: model.performCleanup).disabled(model.cleanupCount == 0)
            }
    }
}
