import AppKit
import SwiftUI
import SaytileKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case archive, speech, models, cloud, input, storage, about
    var id: Self { self }
    var title: String { switch self {
    case .archive: "语音档案"; case .speech: "麦克风"; case .models: "本地模型"; case .cloud: "云端服务"; case .input: "输入与快捷键"; case .storage: "原音与存储"; case .about: "关于"
    } }
    var symbol: String { switch self {
    case .archive: "tray.full"; case .speech: "mic"; case .models: "cpu"; case .cloud: "cloud"; case .input: "keyboard"; case .storage: "internaldrive"; case .about: "info.circle"
    } }
}

@MainActor
final class WorkspaceNavigation: ObservableObject {
    @Published var page: SettingsPage {
        didSet { if page != oldValue { didNavigate?() } }
    }
    var didNavigate: (() -> Void)?
    init(_ page: SettingsPage = .archive) { self.page = page }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var navigation: WorkspaceNavigation
    @ViewState private var cloudService: CloudSettingsService
    init(model: AppModel, initialPage: SettingsPage = .archive, initialCloudService: CloudSettingsService? = nil,
         navigation: WorkspaceNavigation? = nil) {
        self.model = model
        _navigation = StateObject(wrappedValue: navigation ?? WorkspaceNavigation(initialPage))
        _cloudService = ViewState(initialValue: initialCloudService ?? (!model.deviceOnly && !model.hosted.selected ? .byok : .hosted))
    }
    @ViewState private var cleanup = false
    private var page: SettingsPage { navigation.page }
    private var version: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { "内测 \($0)" } ?? "开发构建" }
    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 640
            HStack(spacing: 0) {
                if !compact {
                    VStack(alignment: .leading, spacing: 2) {
                        WorkspaceBrand().frame(maxWidth: .infinity).padding(.vertical, 16)
                        ForEach(SettingsPage.allCases) { item in
                            WorkspaceNavRow(title: item.title, symbol: item.symbol, selected: page == item) { navigation.page = item }
                                .accessibilityIdentifier("settings.page." + item.rawValue)
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 10).frame(width: 164).background(.regularMaterial)
                    Divider()
                }
                VStack(alignment: .leading, spacing: 0) {
                    if compact {
                        ZStack(alignment: .leading) {
                            WorkspaceBrand(compact: true).frame(maxWidth: .infinity)
                            Menu {
                                ForEach(SettingsPage.allCases) { item in
                                    Button { navigation.page = item } label: {
                                        if page == item { Label(item.title, systemImage: "checkmark") }
                                        else { Text(item.title) }
                                    }
                                }
                            } label: {
                                Image(systemName: "sidebar.left")
                                    .frame(width: 32, height: 30).contentShape(Rectangle())
                            }
                            .fixedSize().menuStyle(.borderlessButton).menuIndicator(.hidden)
                            .accessibilityLabel("选择页面").accessibilityValue(page.title)
                            .accessibilityIdentifier("settings.navigation").help("选择页面")
                        }.padding(.horizontal, 16).frame(height: 44)
                        Divider()
                    }
                    if page == .archive {
                        ArchiveView(model: model)
                    } else {
                        Text(page.title).font(WorkspaceStyle.title).accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, 24).padding(.top, compact ? 15 : 25).padding(.bottom, 6)
                        if let notice = model.notice, page != .speech || notice != model.panelCaptureDetail {
                            Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                .padding(.horizontal, 24).padding(.top, 6).accessibilityIdentifier("settings.notice")
                        }
                        Form { settingsContent }.formStyle(.grouped).scrollContentBackground(.hidden).id(page)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.background(WorkspaceStyle.background).foregroundStyle(WorkspaceStyle.foreground).tint(WorkspaceStyle.accent)
            .confirmationDialog("清理 \(model.cleanupCount) 条已识别、未收藏且超过 30 天的原音？已保存的文字会保留。", isPresented: $cleanup, titleVisibility: .visible) {
                Button("清理这些原音", role: .destructive, action: model.performCleanup).disabled(model.cleanupCount == 0)
            }
    }
    @ViewBuilder private var settingsContent: some View {
        switch page {
        case .archive: EmptyView()
        case .speech: speech.onAppear { model.audio.refreshDevices() }
        case .models: LocalModelSettings(model: model)
        case .cloud: cloud
        case .input: input
        case .storage: storage
        case .about: about
        }
    }
    @ViewBuilder private var speech: some View {
        Section {
            Picker("输入设备", selection: $model.deviceUID) {
                ForEach(model.devices) { device in Text(device.name).tag(device.id) }
            }.accessibilityLabel("输入设备").accessibilityIdentifier("settings.inputDevice")
            LabeledContent("麦克风权限") {
                if model.microphoneDenied { Button("打开系统设置…", action: model.openMicrophoneSettings) }
                else { Text(model.microphoneLabel) }
            }
        }
        if let detail = model.panelCaptureDetail {
            Section { Text(detail).textSelection(.enabled).accessibilityIdentifier("settings.captureDetail") }
        }
        if let issue = model.audio.issue, issue != model.notice, issue != model.panelCaptureDetail {
            Section { Text(issue).textSelection(.enabled).accessibilityIdentifier("settings.audioIssue") }
        }
    }
    @ViewBuilder private var cloud: some View {
        Section {
            Picker("配置服务", selection: $cloudService) {
                Text("Saytile Cloud").tag(CloudSettingsService.hosted)
                Text("自带 API").tag(CloudSettingsService.byok)
            }.pickerStyle(.menu).accessibilityIdentifier("cloud.serviceInspector")
        }
        switch cloudService {
        case .hosted: HostedSettingsSection(model: model, account: model.hosted)
        case .byok:
            RecognitionSettingsSection(model: model, managesInputSource: true)
            if model.deviceOnly {
                Section("本机识别的文字核对") {
                    Toggle("用 GPT-6 核对新讲话的文字", isOn: Binding(get: { model.localTextAllowed }, set: { model.allowLocalText($0) }))
                        .disabled(!model.localTextAllowed && model.localGPT.map(model.hasCredential) != true)
                    Text("仅将文字发送给 OpenAI，费用由你的 API 账户承担。").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
    @ViewBuilder private var input: some View {
        Section("直接输入") {
            LabeledContent("辅助功能", value: model.accessibilityLabel)
            LabeledContent("输入目标", value: model.targetLabel).accessibilityIdentifier("settings.inputTarget")
            if !model.input.hasPermission { Button("允许跨应用插入…", action: model.requestAccessibility) }
            Text("复制无需授权。直接输入只追加到你绑定的草稿。") .font(.callout).foregroundStyle(.secondary)
        }
        Section("输入板") {
            Toggle("显示边框", isOn: $model.panelBorderVisible).accessibilityIdentifier("settings.panelBorder")
            Picker("讲话分组间隔", selection: Binding(get: { model.timelineIdleSeconds }, set: { model.changeIdleInterval($0) })) {
                let minutes = [1, 2, 5, 10, 30, 60]
                if !minutes.contains(where: { $0 * 60 == model.timelineIdleSeconds }) {
                    Text("\(model.timelineIdleSeconds) 秒（自定义）").tag(model.timelineIdleSeconds)
                }
                ForEach(minutes, id: \.self) { minute in
                    Text("\(minute) 分钟").tag(minute * 60)
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
            Text("只清理 30 天前已有转写文字、且未收藏的原音。没有转写的录音会保留。").font(.callout).foregroundStyle(.secondary)
        }
        Section { Button("在 Finder 中显示资料目录", action: model.revealData) }
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

enum CloudSettingsService { case hosted, byok }
