import SaytileVoiceUI
import SwiftUI
import AppKit
import SaytileKit

/// Audio levels and hover state update the window much more often than its text.
@MainActor private final class PanelDocumentCache: ObservableObject {
    private var revision: UInt64?
    private var focus: Int64?
    private var cached = PanelTimelineDocument()

    func document(for model: AppModel) -> PanelTimelineDocument {
        if revision != model.timelineRenderRevision || focus != model.timelineFocus {
            let page = model.panelTimelinePage
            cached = PanelTimelineDocument(entries: page.entries, older: page.hasOlder, newer: page.hasNewer)
            if !page.hasNewer, model.timelineFocus == nil, let tail = page.entries.last,
               tail.recording.isRecording, tail.preferredOrigin == .partial {
                cached.liveTailID = tail.id
            }
            revision = model.timelineRenderRevision
            focus = model.timelineFocus
        }
        return cached
    }
}

struct InputPanelView: View {
    @ObservedObject var model: AppModel
    var onExpand: (() -> Void)? = nil
    @ViewState private var followsLatest = true
    @StateObject private var access = PanelTranscriptAccess()
    @StateObject private var transcriptCache = PanelDocumentCache()
    @ViewState private var selectedText = ""
    @ViewState private var latestRequest = 0
    private var document: PanelTimelineDocument {
        transcriptCache.document(for: model)
    }
    private var canCopy: Bool { model.canCopyLatestGroup || !selectedText.isEmpty }
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
            applyEdits: { edits in
                do {
                    try model.editPanelRows(edits.map { PanelRowEdit(id: $0.id, before: $0.before, after: $0.after) })
                    return document
                } catch {
                    model.notice = error.localizedDescription
                    throw error
                }
            }, compactHelp: "点按控制收音，向外拖动左右边缘或从菜单选择“展开语音板”", menu: { panelActions })
    }

    private func copyTranscript() {
        guard canCopy else { return }
        let view = access.view
        model.copyTimeline(selection: view?.selectionSnapshot ?? selectedText, displayed: view?.rendered.displayed ?? [:])
    }

    private func insertTranscript() {
        access.view?.settleLivePresentation()
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
        let action: @MainActor () -> Void
        var copyID: String {
            switch id {
            case "edit", "latest": "panel." + id
            default: "panel.more." + id
            }
        }
    }
    private var commandGroups: [[PanelCommand]] {
        let compactCommands = onExpand.map { [[PanelCommand(id: "expand", title: "展开语音板", action: $0)]] } ?? []
        return compactCommands +
        [
            [.init(id: "copy", title: selectedText.isEmpty ? "复制当前文字" : "复制所选文字", enabled: canCopy, action: { copyTranscript() }),
             .init(id: "edit", title: "在档案中编辑这段文字", enabled: editTarget != nil, action: { if let item = editTarget { model.select(item) } }),
             .init(id: "latest", title: "回到最新", enabled: !followsLatest, action: { model.followTimeline(); latestRequest += 1 })],
            [.init(id: "settings", title: "语音档案与设置…", action: { model.openSettings() })],
            [.init(id: "free", title: "自由记录", checked: !model.directMode, action: { model.setDirect(false) }),
             .init(id: "direct", title: "直接输入", checked: model.directMode, action: { model.setDirect(true) }),
             .init(id: "bind", title: "绑定当前草稿", action: { model.bindTarget() }),
             .init(id: "insert", title: model.isInserting ? "正在插入…" : (model.insertionArchiveEntry == nil ? "插入最新时间组" : "插入档案定位的这段文字"),
                   enabled: !model.isInserting && model.hasPanelInsertionScope, action: insertTranscript)],
            [.init(id: "clear", title: "清空输入板（保留档案）", enabled: !model.isInserting && model.hasPanelInsertionScope, action: { model.clearPanel(); latestRequest += 1 }),
             .init(id: "hide", title: "收起输入板", action: { model.hidePanel() })]
        ]
    }

    @ViewBuilder private var panelActions: some View {
        let groups = commandGroups
        ForEach(groups.indices, id: \.self) { i in
            if i != 0 { Divider() }
            ForEach(groups[i]) { command in
                Button(action: command.action) {
                    if command.checked { Label(command.title, systemImage: "checkmark") }
                    else { Text(command.title) }
                }.disabled(!command.enabled).accessibilityIdentifier(command.copyID)
            }
        }
    }
    private func fillContextMenu(_ menu: NSMenu) {
        for (i, commands) in commandGroups.enumerated() {
            if i != 0 { menu.addItem(.separator()) }
            for command in commands {
                let item = TranscriptMenuItem(title: command.title, identifier: "panel.menu." + command.id, action: command.action)
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

    private var showingFavorites: Bool { model.recordFilter == .pinned }
    var body: some View {
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 720
            HStack(spacing: 0) {
                if sideBySide || model.selected == nil { archiveList }
                if let selected = model.selected {
                    if sideBySide { Divider() }
                    RecordDetailView(item: selected, model: model)
                        .id(selected.id)
                        .frame(maxWidth: sideBySide ? min(360, geometry.size.width * 0.43) : .infinity)
                        .background(WorkspaceStyle.editor.opacity(0.55))
                }
            }
        }
        .background(WorkspaceStyle.background)
        .foregroundStyle(WorkspaceStyle.foreground).tint(WorkspaceStyle.accent)
        .background(Button("") { if model.selected != nil { model.closeDetail() }; searching = true }
            .keyboardShortcut("f").hidden().accessibilityHidden(true))
    }

    private var archiveList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(showingFavorites ? "已收藏" : "语音档案").font(WorkspaceStyle.title).accessibilityAddTraits(.isHeader)
                Spacer()
                ArchiveIconButton(symbol: showingFavorites ? "star.fill" : "star",
                                  label: showingFavorites ? "显示所有语音档案" : "只看已收藏",
                                  id: "archive.favorites", selected: showingFavorites,
                                  action: model.toggleFavoriteFilter)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索文字、历史版本或草稿", text: $model.query)
                    .textFieldStyle(.plain).accessibilityLabel("搜索语音记录").focused($searching)
                    .onSubmit { Task { await model.refresh() } }
                if !model.query.isEmpty {
                    ArchiveIconButton(symbol: "xmark.circle.fill", label: "清除搜索", id: "archive.clearSearch") { model.query = "" }
                }
            }
            .padding(.leading, 10).padding(.trailing, 2).frame(height: 34)
            .background(WorkspaceStyle.editor, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary).allowsHitTesting(false))

            if let notice = model.notice { Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            if model.records.isEmpty {
                ContentUnavailableView(
                    model.query.isEmpty ? (showingFavorites ? "还没有收藏" : model.recordFilter == .all ? "还没有语音记录" : "还没有转写文字") : "没有匹配结果",
                    systemImage: model.query.isEmpty ? (showingFavorites ? "star" : "waveform") : "magnifyingglass",
                    description: Text(model.query.isEmpty ? (showingFavorites ? "点记录旁的星标，即可在这里找到它。" : "讲话转成的文字会按日期显示。") : "试试更短的关键词，或清除搜索。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                archiveRows
            }
            if !showingFavorites && model.query.isEmpty {
                Toggle("包括未转写记录", isOn: Binding(get: { model.recordFilter == .all },
                         set: { model.includeUntranscribed($0) }))
                    .toggleStyle(.checkbox).controlSize(.small)
                    .accessibilityIdentifier("archive.includeUntranscribed")
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var archiveRows: some View {
        let rows = model.records
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { offset, item in
                    if offset == 0 || !Calendar.current.isDate(rows[offset - 1].date, inSameDayAs: item.date) {
                        Text(item.date, format: .dateTime.year().month().day())
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.top, 8).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
                    }
                    ArchiveRow(item: item, model: model)
                    Divider()
                }
                if model.hasMore { Button("加载更早记录", action: model.loadMore).padding(.vertical, 12) }
            }
        }
    }
}

private struct ArchiveIconButton: View {
    let symbol: String
    let label: String
    let id: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? WorkspaceStyle.accent : .secondary)
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label).accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(label)
    }
}

private struct ArchiveFavorite: View {
    let item: DisplayRecording
    let id: String
    @ObservedObject var model: AppModel
    var body: some View {
        ArchiveIconButton(symbol: item.pinned ? "star.fill" : "star", label: item.pinned ? "取消收藏" : "收藏这条记录",
                          id: id, selected: item.pinned) {
            Task { await model.toggleFavorite(item.id) }
        }
    }
}

private struct ArchiveRow: View {
    let item: DisplayRecording
    @ObservedObject var model: AppModel
    var body: some View {
        let hasText = !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 2) {
                Text(item.date, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
                    .accessibilityIdentifier("archive.time.\(item.id)")
                if item.hasAudio {
                    Button { model.play(item) } label: {
                        Label {
                            Text(model.playingID == item.id ? "停止" : "回听 · \(max(1, Int(item.source.duration.rounded()))) 秒")
                        } icon: {
                            Image(systemName: model.playingID == item.id ? "stop.fill" : "play.fill")
                        }
                        .padding(.horizontal, 5).frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.playingID == item.id ? "停止回听" : "回听原音")
                    .accessibilityIdentifier("archive.play.\(item.id)")
                    .help(item.audioLabel)
                }
                Spacer()
                ArchiveFavorite(item: item, id: "archive.favorite.\(item.id)", model: model)
                if hasText {
                    ArchiveIconButton(symbol: "doc.on.doc", label: "复制这段文字", id: "archive.copy.\(item.id)") {
                        model.copy(item.text)
                    }
                }
                ArchiveIconButton(symbol: "square.and.pencil", label: "查看和编辑这段表达", id: "archive.detail.\(item.id)") {
                    Task { await model.selectForEditing(item) }
                }
            }.font(.caption).foregroundStyle(.secondary)
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
        .padding(.top, 4).padding(.bottom, 12)
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
                ArchiveIconButton(symbol: "xmark", label: "返回记录列表", id: "archive.closeDetail", action: model.closeDetail).keyboardShortcut(.cancelAction)
            }
            Text(item.date, format: .dateTime.year().month().day().hour().minute().second()).font(.system(size: 11)).foregroundStyle(.secondary)
            if !item.hasAudio { Text(item.audioLabel).font(.caption).foregroundStyle(.secondary) }
            if let error = item.source.displayedError {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.amber).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            TextEditor(text: Binding(get: { model.editorDraft }, set: { newText in model.updateEditorDraft(newText) })).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(8).background(WorkspaceStyle.editor, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary).allowsHitTesting(false)).frame(minHeight: 135, idealHeight: 180).accessibilityLabel("编辑这段文字").disabled(!model.editorCanEdit)
            Text(model.editorDraftStatus).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                Button(model.savingEditorChanges ? "正在保存…" : "保存修改") { Task { await model.saveEditorChanges() } }.keyboardShortcut("s").buttonStyle(QuietButton(prominent: true)).disabled(!model.editorCanEdit || model.savingEditorChanges || model.editorDraft == item.text)
                ArchiveFavorite(item: item, id: "archive.detailFavorite", model: model)
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
                Button("复制") { model.copy(model.editorDraft) }.disabled(!model.editorCanEdit || model.editorDraft.isEmpty)
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

