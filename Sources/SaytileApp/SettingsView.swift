import AppKit
import SwiftUI
import SaytileKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case speech, models, input, storage, about
    var id: Self { self }
    var title: String { switch self {
    case .speech: "声音与识别"; case .models: "本地模型"; case .input: "输入与快捷键"; case .storage: "原音与存储"; case .about: "关于 Saytile"
    } }
    var symbol: String { switch self {
    case .speech: "waveform"; case .models: "cpu"; case .input: "keyboard"; case .storage: "internaldrive"; case .about: "info.circle"
    } }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ViewState private var page: SettingsPage
    init(model: AppModel, initialPage: SettingsPage = .speech) {
        self.model = model; _page = ViewState(initialValue: initialPage)
    }
    @ViewState private var cleanup = false
    private var version: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { "内测 \($0)" } ?? "开发构建" }
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if geo.size.width >= 640 {
                    VStack(alignment: .leading, spacing: 3) {
                        WorkspaceBrand().padding(.leading, 9).padding(.vertical, 18).padding(.bottom, 7)
                        ForEach(SettingsPage.allCases) { item in
                            WorkspaceNavRow(title: item.title, symbol: item.symbol, selected: page == item) { page = item }
                                .accessibilityIdentifier("settings.page." + item.rawValue)
                        }
                        Spacer()
                    }.padding(.horizontal, 12).padding(.top, 4).frame(width: 164).background(.regularMaterial)
                    Divider()
                }
                VStack(alignment: .leading, spacing: 0) {
                    if geo.size.width < 640 {
                        HStack { WorkspaceBrand(); Spacer(); Picker("设置项目", selection: $page) {
                            ForEach(SettingsPage.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().fixedSize().accessibilityIdentifier("settings.navigation") }
                            .padding(.horizontal, 24).padding(.top, 16)
                    }
                    Text(page.title).font(WorkspaceStyle.title).accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 24).padding(.top, geo.size.width < 640 ? 15 : 25).padding(.bottom, 6)
                    if let notice = model.notice {
                        Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            .padding(.horizontal, 24).padding(.top, 6).accessibilityIdentifier("settings.notice")
                    }
                    Form {
                        switch page {
                        case .speech: speech
                        case .models: LocalModelSettings(model: model)
                        case .input: input
                        case .storage: storage
                        case .about: about
                        }
                    }.formStyle(.grouped).scrollContentBackground(.hidden).id(page)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.background(WorkspaceStyle.background).foregroundStyle(WorkspaceStyle.foreground).tint(WorkspaceStyle.accent)
            .onReceive(NotificationCenter.default.publisher(for: .init("SaytileOpenStorageSettings"))) { _ in page = .storage }
            .confirmationDialog("清理 \(model.cleanupCount) 条已识别、未收藏且超过 30 天的原音？已保存的文字会保留。", isPresented: $cleanup, titleVisibility: .visible) {
                Button("清理这些原音", role: .destructive, action: model.performCleanup).disabled(model.cleanupCount == 0)
            }
    }
    @ViewBuilder private var speech: some View {
        Section("麦克风") {
            Picker("输入设备", selection: $model.deviceUID) {
                ForEach(model.devices) { device in Text(device.name).tag(device.id) }
            }.accessibilityLabel("输入设备").accessibilityIdentifier("settings.inputDevice")
            LabeledContent("收音", value: model.captureLabel)
            if let detail = model.panelCaptureDetail { Text(detail).foregroundStyle(.secondary).accessibilityIdentifier("settings.captureDetail") }
            LabeledContent("麦克风权限") {
                if model.microphoneDenied { Button("打开系统设置…", action: model.openMicrophoneSettings) }
                else { Text(model.microphoneLabel) }
            }
            Button(model.captureActionLabel, action: model.toggleCapture)
        }
        HostedSettingsSection(model: model, account: model.hosted)
        if model.deviceOnly {
            LabeledContent("识别语言", value: "中文 · 本机处理")
            Button("管理本地模型") { page = .models }.accessibilityIdentifier("settings.manageModels")
        } else if !model.hosted.selected {
            RecognitionSettingsSection(model: model)
        }
    }
    @ViewBuilder private var input: some View {
        Section("直接输入") {
            LabeledContent("辅助功能", value: model.accessibilityLabel)
            if !model.input.hasPermission { Button("允许跨应用插入…", action: model.requestAccessibility) }
            Text("复制无需授权。直接输入只追加到你绑定的草稿。") .font(.callout).foregroundStyle(.secondary)
        }
        Section("输入板") {
            Toggle("显示边框", isOn: $model.panelBorderVisible).accessibilityIdentifier("settings.panelBorder")
            Picker("讲话分组间隔", selection: Binding(get: { model.timelineIdleSeconds }, set: { model.changeIdleInterval($0) })) {
                ForEach([10, 30, 60, 120, 300, 600, 1800, 3600], id: \.self) { seconds in
                    Text(seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分钟").tag(seconds)
                }
            }.accessibilityIdentifier("settings.timelineIdle")
            Picker("展开或收起", selection: $model.shortcutChoice) {
                Text("⌥ 空格").tag("option-space"); Text("⌃ ⌥ 空格").tag("control-option-space")
                Text("⌘ ⇧ 空格").tag("command-shift-space"); Text("关闭快捷键").tag("disabled")
            }
            Toggle("显示桌面语音入口", isOn: $model.floatingEntryEnabled).accessibilityIdentifier("settings.floatingEntry")
        }
        Section("启动") {
            Toggle("登录时启动 Saytile", isOn: Binding(get: { model.launchAtLogin }, set: { enabled in model.setLoginItem(enabled) })).disabled(!model.canManageLoginItem)
            if !model.canManageLoginItem { Text("体验版从应用程序手动打开。").font(.callout).foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private var storage: some View {
        Section("原音") {
            LabeledContent("使用空间", value: model.storageLabel)
            LabeledContent("保留时间", value: "直到手动删除")
            Text("达到 10 GB 时提醒。删除原音会保留文字与修改版本。").font(.callout).foregroundStyle(.secondary)
            Button(model.preparingCleanup ? "正在查找原音…" : "预览可清理的原音…") { Task { cleanup = await model.previewCleanup() } }.disabled(model.preparingCleanup)
            Text("可清理 30 天前已识别且未收藏的原音。").font(.callout).foregroundStyle(.secondary)
        }
        Section("档案") { Button("打开语音档案", action: model.openArchive); Button("在 Finder 中显示资料目录", action: model.revealData) }
    }
    @ViewBuilder private var about: some View {
        Section {
            LabeledContent("版本", value: version).textSelection(.enabled)
            if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String { LabeledContent("构建", value: build) }
            if let check = model.checkForUpdates { Button("检查更新…", action: check) }
            else { LabeledContent("更新", value: "手动安装") }
        }
        Section("诊断信息") {
            LabeledContent("识别状态", value: model.engineLabel)
            if let revision = Bundle.main.object(forInfoDictionaryKey: "SaytileSourceRevision") as? String {
                LabeledContent("源码版本", value: String(revision.prefix(12))).textSelection(.enabled)
            }
        }
    }
}
