import SwiftUI
import SaytileKit

struct RecognitionSettingsSection: View {
    @ObservedObject var model: AppModel
    var initiallyExpanded = false
    var allowsAutomaticRecovery = true
    @ViewState private var servicesExpanded = false
    @ViewState private var credentialStates: [UUID: CloudCredentialPresence] = [:]
    private var active: [ModelConfiguration] { model.recognitionConfiguration.enabledModels }
    private var preparedCount: Int {
        active.filter { $0.cloudConsent && credentialStates[$0.id] == .saved && (try? $0.validate()) != nil }.count
    }
    var body: some View {
        Section("AI 识别") {
            Toggle("启用高质量云端识别", isOn: $model.recognitionConfiguration.cloudEnabled)
                .accessibilityIdentifier("recognition.cloudEnabled")
            HStack {
                Label("已准备 \(preparedCount) / \(active.count) 项服务", systemImage: "checklist")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(servicesExpanded ? "收起连接设置" : "连接识别服务") { servicesExpanded.toggle() }
                    .accessibilityIdentifier("recognition.configureServices")
            }
            Picker("输入确认", selection: $model.recognitionConfiguration.inputMode) {
                ForEach(InputQualityMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("recognition.inputMode")
            Text(model.recognitionConfiguration.inputMode == .highestQuality
                 ? "讲话时持续显示文字；模型共同确认后才输入目标应用。疑难内容保留在板内，等待复核。"
                 : "优先输入较快的稳定结果。之后的准确版本保存在 Saytile，已输入内容不会被悄悄替换。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            TextField("当前话题或术语提示（可选）", text: $model.recognitionConfiguration.topicContext, axis: .vertical)
                .lineLimit(2...4).accessibilityIdentifier("recognition.topicContext")
            if servicesExpanded {
                Text("中文、英文同时识别，AI 融合与原音复核协助确认，高精度定稿保留为文字版本。密钥仅存于钥匙串，真实连接结果会在识别时显示。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                ForEach($model.recognitionConfiguration.models) { $item in
                    if !item.isOptionalExpert {
                        ModelConfigurationEditor(configuration: $item, model: model, onCredentialChange: refreshPresence)
                    }
                }
                DisclosureGroup("其他识别专家与自定义服务") {
                    ForEach($model.recognitionConfiguration.models) { $item in
                        if item.isOptionalExpert {
                            ModelConfigurationEditor(configuration: $item, model: model, onCredentialChange: refreshPresence)
                        }
                    }
                    Button("添加自定义模型") {
                        model.recognitionConfiguration.models.append(.init(purpose: .multilingualASR, provider: .soniox, model: "stt-rt-v6", enabled: false))
                        refreshPresence()
                    }.accessibilityIdentifier("recognition.addModel")
                }
            }
            Toggle("连接中断后从已保存原音自动恢复", isOn: $model.recognitionConfiguration.automaticRecovery)
                .accessibilityIdentifier("recognition.automaticRecovery")
                .disabled(!allowsAutomaticRecovery)
            Text("每项服务独立授权。启用后，语音或必要候选文字将交给所选服务处理，费用由你的服务商账户承担。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            Button(model.applyingRecognitionSettings ? "正在应用…" : "保存并应用识别设置", action: model.applyRecognitionSettings)
                .disabled(model.applyingRecognitionSettings)
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
            DisclosureGroup("最近模型调用与用量") {
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
}

struct ModelConfigurationEditor: View {
    @Binding var configuration: ModelConfiguration
    @ObservedObject var model: AppModel
    var initiallyExpanded = false
    var onCredentialChange: () -> Void = {}
    @ViewState private var secret = ""
    @ViewState private var credentialPresence: CloudCredentialPresence = .missing
    @ViewState private var expanded = false
    private var prefix: String { "recognition.model." + configuration.id.uuidString.lowercased() }
    private var status: String {
        if !configuration.enabled { return "已停用" }
        if credentialPresence != .saved { return credentialPresence.label }
        if !configuration.cloudConsent { return "待授权" }
        if (try? configuration.validate()) == nil { return "待完善设置" }
        return "已准备"
    }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Toggle("使用此模型", isOn: $configuration.enabled).accessibilityIdentifier(prefix + ".enabled")
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
                Picker("职责", selection: Binding(get: { configuration.purpose }, set: { purpose in
                    configuration.purpose = purpose; configuration.cloudConsent = false
                    if !configuration.provider.supports(purpose), let provider = CloudProvider.allCases.first(where: { $0.supports(purpose) }) {
                        selectProvider(provider)
                    }
                })) {
                    ForEach(RecognitionPurpose.allCases, id: \.self) { Text($0.label).tag($0) }
                }.accessibilityIdentifier(prefix + ".purpose")
                Picker("服务", selection: Binding(get: { configuration.provider }, set: { provider in selectProvider(provider) })) {
                    ForEach(CloudProvider.allCases.filter { $0.supports(configuration.purpose) }, id: \.self) { Text($0.label).tag($0) }
                }.accessibilityIdentifier(prefix + ".provider")
                TextField("模型 ID", text: $configuration.model).autocorrectionDisabled()
                    .accessibilityIdentifier(prefix + ".modelID")
                TextField("此模型的术语提示（可选）", text: $configuration.context, axis: .vertical).lineLimit(1...3)
                if configuration.purpose == .textFusion {
                    Picker("推理强度", selection: $configuration.reasoningEffort) {
                        Text("High").tag("high"); Text("Extra high").tag("xhigh"); Text("Max").tag("max")
                    }
                    Picker("推理模式", selection: $configuration.reasoningMode) {
                        Text("Standard").tag("standard"); Text("Pro · 允许更长复核").tag("pro")
                    }
                }
                DisclosureGroup("可选费用估算") {
                    TextField("币种", text: $configuration.currency)
                    rateField("每音频/会话小时单价", value: $configuration.audioHourRate)
                    rateField("每百万输入 Token 单价", value: $configuration.inputMillionTokenRate)
                    rateField("每百万输出 Token 单价", value: $configuration.outputMillionTokenRate)
                    Text("按填写单价估算；优惠、最低计费和真实账单可能不同。不填写时费用显示未知。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
        } label: {
            HStack {
                Text(configuration.purpose.label + " · " + configuration.provider.label)
                Spacer()
                Text(status).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
            .task { credentialPresence = model.credentialPresence(configuration); expanded = initiallyExpanded }
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
