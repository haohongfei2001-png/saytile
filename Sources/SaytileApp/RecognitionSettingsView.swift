import SwiftUI
import SaytileKit

struct RecognitionSettingsSection: View {
    @ObservedObject var model: AppModel
    var initiallyExpanded = false
    var allowsAutomaticRecovery = true
    @ViewState private var servicesExpanded = false
    @ViewState private var credentialStates: [UUID: CloudCredentialPresence] = [:]
    private var active: [ModelConfiguration] { model.recognitionConfiguration.activeModels }
    private var preparedCount: Int {
        active.filter { $0.cloudConsent && credentialStates[$0.id] == .saved && (try? $0.validate()) != nil }.count
    }
    var body: some View {
        Section("AI 识别") {
            Picker("识别语言", selection: Binding(get: { model.recognitionConfiguration.languagePreference ?? .auto }, set: { model.recognitionConfiguration.languagePreference = $0 })) {
                ForEach(LanguagePreference.allCases, id: \.self) { preference in
                    Text(preference.label).tag(preference)
                }
            }.accessibilityIdentifier("recognition.languagePreference")
            Toggle("启用高质量云端识别", isOn: $model.recognitionConfiguration.cloudEnabled)
                .disabled(!model.connectionVerified || model.checkingConnection)
                .accessibilityIdentifier("recognition.cloudEnabled")
            HStack {
                Label("已准备 \(preparedCount) / \(active.count) 项服务", systemImage: "checklist")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(servicesExpanded ? "收起连接设置" : "连接识别服务") { servicesExpanded.toggle() }
                    .accessibilityIdentifier("recognition.configureServices")
            }
            TextField("当前话题或术语提示（可选）", text: $model.recognitionConfiguration.topicContext, axis: .vertical)
                .lineLimit(2...4).accessibilityIdentifier("recognition.topicContext")
            if servicesExpanded {
                Text("每段录音只使用一项 ASR 服务，按语言偏好自动选择；GPT-6 只处理候选文字。密钥仅存于钥匙串。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                if model.recognitionConfiguration.selectedASRModel == nil {
                    Text("自动模式尚无足够语言记录。可以继续本机识别，或选择讲话语言后连接对应服务。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                ForEach($model.recognitionConfiguration.models) { $item in
                    if active.contains(where: { $0.id == item.id }) {
                        ModelConfigurationEditor(configuration: $item, model: model, onCredentialChange: refreshPresence)
                    }
                }
                ConnectionCheckPanel(model: model, ready: preparedCount == 2 && active.count == 2)
            }
            Toggle("连接中断后从已保存原音自动恢复", isOn: $model.recognitionConfiguration.automaticRecovery)
                .accessibilityIdentifier("recognition.automaticRecovery")
                .disabled(!allowsAutomaticRecovery)
            Text("以前仅在本机处理的原音仍在本机恢复。更换服务、地区或密钥不会自动上传旧档案；需要时可在档案中选择用云端重新识别。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            Text("每项服务独立授权。启用后，语音或必要候选文字将交给所选服务处理，费用由你的服务商账户承担。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            Button(model.applyingRecognitionSettings ? "正在应用…" : "保存并应用识别设置", action: model.applyRecognitionSettings)
                .disabled(model.applyingRecognitionSettings || model.checkingConnection)
                .accessibilityIdentifier("recognition.apply")
            if model.hasUnappliedRecognitionSettings {
                Text("有尚未应用的修改").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("recognition.unapplied")
            }
            Text("修改在保存并应用后生效；移除密钥会立即停止相关云端运行。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            if let note = model.recognitionSettingsNotice {
                Text(note).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("recognition.notice")
            }
            DisclosureGroup("服务用量记录") {
                if model.modelCallSummary.isEmpty { Text("尚无模型调用。未返回账单金额时显示未知，不记为零费用。").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                ForEach(Array(model.modelCallSummary.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 11)).textSelection(.enabled)
                }
            }
        }.task { servicesExpanded = initiallyExpanded; refreshPresence() }
            .onChange(of: model.recognitionSettingsNotice) { _, _ in refreshPresence() }
    }
    private func refreshPresence() {
        var updated: [UUID: CloudCredentialPresence] = [:]
        for item in model.recognitionConfiguration.models { updated[item.id] = model.credentialPresence(item) }
        credentialStates = updated
    }
}

private extension ModelConfiguration {
    var isOptionalExpert: Bool { provider == .soniox || provider == .meta }
    var isLegacyReviewModel: Bool { [.audioReview, .finalASR].contains(purpose) }
}

struct ModelConfigurationEditor: View {
    @Binding var configuration: ModelConfiguration
    @ObservedObject var model: AppModel
    var initiallyExpanded = false
    var onCredentialChange: () -> Void = {}
    @ViewState private var secret = ""
    @ViewState private var credentialPresence: CloudCredentialPresence = .missing
    @ViewState private var expanded = false
    init(configuration: Binding<ModelConfiguration>, model: AppModel, initiallyExpanded: Bool = false,
         onCredentialChange: @escaping () -> Void = {}) {
        _configuration = configuration; _model = ObservedObject(wrappedValue: model)
        self.initiallyExpanded = initiallyExpanded; self.onCredentialChange = onCredentialChange
        _expanded = ViewState(initialValue: initiallyExpanded)
    }
    private var prefix: String { "recognition.model." + configuration.id.uuidString.lowercased() }
    private var status: String {
        if !model.recognitionConfiguration.activeModels.contains(where: { $0.id == configuration.id }) { return "待选择" }
        if credentialPresence != .saved { return credentialPresence.label }
        if !configuration.cloudConsent { return "待授权" }
        if (try? configuration.validate()) == nil { return "待完善设置" }
        return "已准备"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { expanded.toggle() } label: {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                    Text(configuration.purpose == .textFusion ? "GPT-6 AI 核心" : configuration.purpose.label)
                    Spacer()
                    Text(status).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier(prefix + ".header")
                .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
            if configuration.provider == .qwenMessage {
                Picker("地域", selection: Binding(get: { configuration.region }, set: {
                    configuration.region = $0; configuration.cloudConsent = false
                })) {
                    Text("北京").tag("cn-beijing"); Text("新加坡").tag("ap-southeast-1")
                }.accessibilityIdentifier(prefix + ".region")
                TextField("Workspace ID", text: $configuration.workspaceID).autocorrectionDisabled()
                    .accessibilityIdentifier(prefix + ".workspace")
            } else if configuration.provider == .assemblyAI {
                Picker("地域", selection: Binding(get: { configuration.region }, set: {
                    configuration.region = $0; configuration.cloudConsent = false
                })) {
                    Text("全球").tag("global"); Text("欧盟").tag("eu")
                }.accessibilityIdentifier(prefix + ".region")
            }
            HStack {
                SecureField(credentialPresence == .saved ? "密钥已保存，填写可替换" : "此服务的 API Key", text: $secret)
                    .accessibilityIdentifier(prefix + ".secret")
                Button("保存密钥") {
                    if model.saveCredential(secret, for: configuration) { secret = "" }
                    refreshPresence()
                }.disabled(secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier(prefix + ".saveKey")
                if credentialPresence != .missing {
                    Button("移除") { _ = model.removeCredential(for: configuration); refreshPresence() }
                        .accessibilityIdentifier(prefix + ".removeKey")
                }
            }
            Text(credentialPresence.label).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Toggle(configuration.purpose == .textFusion ? "允许此服务处理候选文字与当前话题" : "允许此服务处理语音和必要上下文（含恢复与复核）",
                   isOn: $configuration.cloudConsent).accessibilityIdentifier(prefix + ".consent")
            DisclosureGroup("高级设置") {
                TextField("此模型的术语提示（可选）", text: $configuration.context, axis: .vertical).lineLimit(1...3)
                DisclosureGroup("可选费用估算") {
                    TextField("币种", text: $configuration.currency)
                    rateField("每音频/会话小时单价", value: $configuration.audioHourRate)
                    rateField("每百万输入 Token 单价", value: $configuration.inputMillionTokenRate)
                    rateField("每百万输出 Token 单价", value: $configuration.outputMillionTokenRate)
                    Text("按填写单价估算；优惠、最低计费和真实账单可能不同。不填写时费用显示未知。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            }
        }
            .task { credentialPresence = model.credentialPresence(configuration) }
    }
    private func selectProvider(_ provider: CloudProvider) {
        configuration.provider = provider
        configuration.resetForProviderChange()
        secret = ""; refreshPresence()
    }
    private func refreshPresence() {
        credentialPresence = model.credentialPresence(configuration)
        onCredentialChange()
    }
    private func rateField(_ title: String, value: Binding<Double?>) -> some View {
        TextField(title, text: Binding(get: { value.wrappedValue.map { String($0) } ?? "" },
                                      set: { value.wrappedValue = Double($0) })).autocorrectionDisabled()
    }
}

private func connectionRoleLabel(_ provider: CloudProvider) -> String {
    switch provider {
    case .qwenMessage: "中文识别"
    case .assemblyAI: "英文识别"
    case .soniox: "中英混说识别"
    case .openAIResponses: "GPT-6 AI 核心"
    default: provider.label
    }
}

private struct ConnectionCheckPanel: View {
    @ObservedObject var model: AppModel
    let ready: Bool
    @ViewState private var costsExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.connectionVerified ? "已接通，可以使用" : "最后一步 · 自动检查连接",
                  systemImage: model.connectionVerified ? "checkmark.circle.fill" : "network")
                .font(.system(size: 13, weight: .semibold))
            Text("不需要你录音。保存当前语言的一项 ASR 密钥和 GPT-6 密钥并授权后，Saytile 会用内置合成语音检查接收、AI 辅助和定稿。全部通过后自动启用；检查期间可以继续使用本机识别。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            if let report = model.connectionReport {
                ForEach(report.services) { service in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(connectionRoleLabel(service.provider))
                            Spacer()
                            Text(service.state.label).foregroundStyle(service.state == .failed ? Color.orange : Palette.muted)
                        }.font(.system(size: 12))
                        if let message = service.message { Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                    }.accessibilityIdentifier("connection.check." + service.provider.rawValue)
                }
                if !model.checkingConnection && !report.transcript.isEmpty {
                    DisclosureGroup("查看合成语音检查结果") {
                        Text(report.transcript).textSelection(.enabled)
                        Text("这是连接与转写流程验证，尚未代表真实讲话准确率。")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }
            }
            Button { costsExpanded.toggle() } label: {
                HStack {
                    Image(systemName: costsExpanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold))
                    Text("检查范围与费用")
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("connection.checkCosts")
                .accessibilityValue(costsExpanded ? "已展开" : "已收起")
            if costsExpanded {
                Text(ConnectionCheckLimits.disclosure).font(.system(size: 11)).foregroundStyle(Palette.muted)
                Text("语音服务可能按会话或音频 Token 计费；取消会关闭连接，不能撤销服务商已处理的请求。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Toggle("同意上传内置合成语音和候选文字，并承担本次检查的服务商费用", isOn: $model.connectionCheckAuthorized)
                .font(.system(size: 12)).disabled(model.checkingConnection)
                .accessibilityIdentifier("connection.authorizeCheck")
            HStack {
                if model.checkingConnection {
                    ProgressView().controlSize(.small)
                    Text("正在检查…").font(.system(size: 12))
                    Spacer()
                    Button("停止检查", action: model.cancelConnectionCheck).accessibilityIdentifier("connection.cancelCheck")
                } else {
                    Button(model.connectionVerified ? "重新检查连接" : "授权并连接", action: model.checkRecognitionConnections)
                        .buttonStyle(.borderedProminent)
                        .disabled(!ready || !model.connectionCheckAuthorized || model.applyingRecognitionSettings)
                        .accessibilityIdentifier("connection.startCheck")
                    if !ready { Text("请先选择讲话语言，保存两项服务的密钥并分别授权").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                }
            }
        }.padding(14).background(Palette.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }
}
