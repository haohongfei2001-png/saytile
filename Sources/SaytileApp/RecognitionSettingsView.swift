import SwiftUI
import SaytileKit

struct RecognitionSettingsSection: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Section("AI 识别") {
            Toggle("启用高质量云端识别", isOn: $model.recognitionConfiguration.cloudEnabled)
            Picker("输入确认", selection: $model.recognitionConfiguration.inputMode) {
                ForEach(InputQualityMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Text(model.recognitionConfiguration.inputMode == .highestQuality
                 ? "讲话时持续显示文字；模型共同确认后才输入目标应用。疑难内容会保留原文并等待复核。"
                 : "优先输入较快的稳定结果。之后的准确版本保存在 Saytile，已输入内容不会被悄悄替换。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            TextField("当前话题或术语提示（可选）", text: $model.recognitionConfiguration.topicContext, axis: .vertical)
                .lineLimit(2...4)
            DisclosureGroup("服务与 API Key") {
                ForEach($model.recognitionConfiguration.models) { $item in
                    ModelConfigurationEditor(configuration: $item, model: model)
                }
                Button("添加模型") {
                    model.recognitionConfiguration.models.append(.init(purpose: .multilingualASR, provider: .soniox, model: "stt-rt-v6"))
                }
            }
            Toggle("连接中断后从已保存原音自动恢复", isOn: $model.recognitionConfiguration.automaticRecovery)
            Text("每项服务独立授权。启用后，将语音或必要候选文字交给所选服务处理，费用由你的服务商账户承担。账户权限、地域和余量由各服务商决定。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            Button("保存并应用识别设置", action: model.applyRecognitionSettings)
            if let note = model.recognitionSettingsNotice { Text(note).font(.system(size: 12)).foregroundStyle(Palette.muted) }
            DisclosureGroup("最近模型调用与用量") {
                if model.modelCallSummary.isEmpty { Text("尚无模型调用。未返回账单金额时显示未知，不记为零费用。").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                ForEach(Array(model.modelCallSummary.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 11)).textSelection(.enabled)
                }
            }
        }
    }
}

private struct ModelConfigurationEditor: View {
    @Binding var configuration: ModelConfiguration
    @ObservedObject var model: AppModel
    @State private var secret = ""
    @State private var credentialPresent = false
    var body: some View {
        DisclosureGroup(configuration.purpose.label) {
            Toggle("使用此模型", isOn: $configuration.enabled)
            Picker("职责", selection: $configuration.purpose) {
                ForEach(RecognitionPurpose.allCases, id: \.self) { Text($0.label).tag($0) }
            }.onChange(of: configuration.purpose) { _, purpose in
                configuration.cloudConsent = false
                if !configuration.provider.supports(purpose), let provider = CloudProvider.allCases.first(where: { $0.supports(purpose) }) {
                    configuration.provider = provider
                }
            }
            Picker("服务", selection: $configuration.provider) {
                ForEach(CloudProvider.allCases.filter { $0.supports(configuration.purpose) }, id: \.self) { Text($0.label).tag($0) }
            }.onChange(of: configuration.provider) { _, _ in
                configuration.cloudConsent = false
                secret = ""; credentialPresent = model.hasCredential(configuration)
                configuration.model = ""
            }
            TextField("模型 ID", text: $configuration.model).autocorrectionDisabled()
            if configuration.provider == .qwenMessage {
                Picker("地域", selection: $configuration.region) {
                    Text("北京").tag("cn-beijing"); Text("新加坡").tag("ap-southeast-1")
                }
                TextField("Workspace ID", text: $configuration.workspaceID).autocorrectionDisabled()
            }
            HStack {
                SecureField(credentialPresent ? "密钥已保存，填写可替换" : "此服务的 API Key", text: $secret)
                Button("保存密钥") {
                    model.saveCredential(secret, for: configuration)
                    secret = ""; credentialPresent = model.hasCredential(configuration)
                }.disabled(secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if credentialPresent {
                    Button("移除") { model.removeCredential(for: configuration); credentialPresent = false }
                }
            }
            Toggle(configuration.purpose == .textFusion ? "允许此服务处理候选文字与当前话题" : "允许此服务处理语音和必要上下文（含恢复与复核）",
                   isOn: $configuration.cloudConsent)
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
        }.task { credentialPresent = model.hasCredential(configuration) }
    }
    private func rateField(_ title: String, value: Binding<Double?>) -> some View {
        TextField(title, text: Binding(get: { value.wrappedValue.map { String($0) } ?? "" },
                                      set: { value.wrappedValue = Double($0) })).autocorrectionDisabled()
    }
}
