import SwiftUI
import AppKit

struct InputPanelView: View {
    @ObservedObject var model: AppModel
    @ViewState private var showNew = false
    @ViewState private var follow = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                VoiceMark(active: model.isListening, size: 19)
                Text("此刻").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: model.openArchive) { Image(systemName: "clock.arrow.circlepath") }.help("语音档案").accessibilityLabel("打开语音档案")
                Button { model.hidePanel() } label: { Image(systemName: "minus") }.help("收起输入板，继续待命").accessibilityLabel("收起输入板")
            }.buttonStyle(.plain).padding(18)
            HStack(spacing: 4) {
                modeButton("自由记录", icon: "waveform", direct: false)
                modeButton("直接输入", icon: "scope", direct: true)
            }.padding(4).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 18)
            if model.directMode {
                HStack {
                    Image(systemName: "arrow.up.forward.app")
                    Text(model.targetLabel).lineLimit(2)
                    Spacer()
                    Button("绑定当前草稿", action: model.bindTarget).buttonStyle(.plain)
                }.font(.system(size: 11)).foregroundStyle(Palette.green).padding(12).background(Palette.soft).padding(.top, 12)
            }
            if let message = model.notice {
                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.font(.system(size: 11)).foregroundStyle(Palette.amber).padding(12).background(Palette.amber.opacity(0.06))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(Date.now, format: .dateTime.month().day()).foregroundStyle(Palette.muted)
                            Spacer()
                            StatePill(text: model.captureLabel, warning: model.captureProblem)
                        }.font(.system(size: 11))
                        if model.recent.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "waveform.path").font(.system(size: 45, weight: .ultraLight)).foregroundStyle(Palette.green.opacity(0.4))
                                Text("想到了，就说出来。").font(.system(size: 20, weight: .medium))
                                Text(model.hasStarted ? "声音会留在这里。\n你可以随时停顿，再接着说。" : "开启后持续接收讲话。\n原音与文字独立保存，随时可以暂停。")
                                    .font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(5)
                                if !model.isListening {
                                    Button("开启自由记录", action: model.toggleCapture).buttonStyle(QuietButton(prominent: true))
                                }
                            }.frame(maxWidth: .infinity).padding(.vertical, 38)
                        }
                        if model.panelHasMore {
                            Button(model.loadingPanel ? "正在载入…" : "载入本次更早的表达（共 \(model.panelCount) 段）", action: model.loadEarlierPanel)
                                .buttonStyle(QuietButton()).disabled(model.loadingPanel)
                            Text("复制与插入仅包含已载入的 \(model.recent.count) 段。更早内容仍保留在档案中。")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                        ForEach(model.recent) { item in
                            TranscriptCard(item: item, model: model, compact: true)
                        }
                        Color.clear.frame(height: 1).id("tail")
                    }.padding(18)
                }
                .onScrollPhaseChange { _, phase in if phase == .interacting { follow = false } }
                .onChange(of: model.recent.count) { _, _ in
                    if follow { proxy.scrollTo("tail", anchor: .bottom) } else { showNew = true }
                }
                .overlay(alignment: .bottom) {
                    if showNew {
                        Button { follow = true; showNew = false; proxy.scrollTo("tail", anchor: .bottom) } label: { Label("查看新内容", systemImage: "arrow.down") }
                            .buttonStyle(QuietButton()).padding(8)
                    }
                }
            }
            Divider().opacity(0.5)
            VStack(spacing: 12) {
                HStack {
                    Label(model.saveLabel, systemImage: "externaldrive.badge.checkmark")
                    Spacer()
                    Menu {
                        Button("清空输入板（保留档案）", action: model.clearPanel).disabled(model.isInserting || model.recent.isEmpty)
                    } label: { Text(model.panelScopeLabel) }
                        .menuStyle(.borderlessButton).fixedSize()
                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                HStack {
                    Button(action: model.openSettings) { Image(systemName: "slider.horizontal.3") }.buttonStyle(.plain).help("设置").accessibilityLabel("设置")
                    Button(action: model.toggleCapture) { Image(systemName: model.isListening ? "pause.circle" : "play.circle") }.buttonStyle(.plain).help(model.isListening ? "暂停收音" : "恢复收音")
                    Spacer()
                    Button { model.copyRecent() } label: { Label("复制", systemImage: "doc.on.doc") }.buttonStyle(QuietButton()).disabled(model.recent.allSatisfy { $0.text.isEmpty })
                    Button { model.insertRecent() } label: { Label(model.isInserting ? "正在插入…" : "插入草稿", systemImage: "arrow.up.right") }.buttonStyle(QuietButton(prominent: true)).disabled(model.isInserting || model.recent.allSatisfy { $0.text.isEmpty })
                }
            }.padding(16)
        }.background(Palette.paper).foregroundStyle(Palette.ink).frame(minWidth: 360, idealWidth: 400, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
    }
    func modeButton(_ label: String, icon: String, direct: Bool) -> some View {
        Button { model.setDirect(direct) } label: {
            Label(label, systemImage: icon).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(model.directMode == direct ? Palette.paper : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityLabel(label)
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
                Text(model.recognitionPhaseLabel(for: item)).font(.system(size: 10))
            }.foregroundStyle(Palette.muted)
            Text(item.text.isEmpty ? item.emptyTextLabel : item.text)
                .font(.system(size: compact ? 14 : 15)).lineSpacing(6).textSelection(.enabled)
                .foregroundStyle(item.text.isEmpty ? Palette.muted : Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
            if let inputLabel = model.insertionLabels[item.id] {
                Label(inputLabel, systemImage: "arrow.up.forward.app").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !compact, !model.query.isEmpty, !item.text.localizedCaseInsensitiveContains(model.query) {
                Text("匹配来自历史版本或已保留的编辑草稿").font(.system(size: 10)).foregroundStyle(Palette.green)
            }
            HStack(spacing: 14) {
                Label(item.audioLabel, systemImage: item.hasAudio ? "waveform" : "text.alignleft").font(.system(size: 10))
                Spacer()
                Button { model.play(item) } label: { Image(systemName: model.playingID == item.id ? "stop.fill" : "play.fill") }.disabled(!item.hasAudio).help("回听原音").accessibilityLabel(model.playingID == item.id ? "停止回听" : "回听原音")
                Button { model.copy(item.text) } label: { Image(systemName: "doc.on.doc") }.disabled(item.text.isEmpty).help("复制文字").accessibilityLabel("复制这段文字")
                Button { model.select(item) } label: { Image(systemName: "ellipsis") }.help("查看、修改及更多操作").accessibilityLabel("查看和编辑这段表达")
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(14).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.green.opacity(0.09)))
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
                    TextField("搜索当前文字与历史版本", text: $model.query).textFieldStyle(.plain)
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
                Button("重新识别") { model.retry(item) }.disabled(!item.hasAudio || item.isRecording)
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
            .confirmationDialog("删除这条记录的全部文字、版本和原音？此操作无法撤销。", isPresented: $deletingRecord, titleVisibility: .visible) {
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
                    Picker("输入设备", selection: $model.deviceID) { ForEach(model.devices) { device in Text(device.name).tag(device.id) } }
                    Text("开启后持续接收讲话；关闭输入板不会停止收音。设备断开、休眠和用户会话切换会明确暂停。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    LabeledContent("识别语言", value: model.appliedRecognitionConfiguration.cloudEnabled ? "中文 / English · 自动处理混说" : "普通话 · 本机备用")
                    LabeledContent("识别引擎", value: model.engineLabel)
                    Button("准备中文识别资源", action: model.prepareSpeech)
                    Button(model.isListening ? "暂停收音" : "开启收音", action: model.toggleCapture)
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
            .confirmationDialog("清理 \(model.cleanupCount) 条已识别、未收藏且超过 30 天的原音？全部文字和版本会保留。", isPresented: $cleanup, titleVisibility: .visible) {
                Button("清理这些原音", role: .destructive, action: model.performCleanup).disabled(model.cleanupCount == 0)
            }
    }
}
