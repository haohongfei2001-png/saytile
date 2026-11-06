import SwiftUI
import SaytileKit

struct ConnectionSetupView: View {
    @ObservedObject var model: AppModel
    let request: ConnectionSetupRequest
    let finish: () -> Void
    @ViewState private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("连接最高质量识别").font(.system(size: 23, weight: .semibold))
                Text("在这里保存密钥并选择服务授权。此窗口不会录音、上传音频或发起模型请求，也不会替换现有 Saytile。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            Form {
                RecognitionSettingsSection(model: model, initiallyExpanded: true, allowsAutomaticRecovery: false)
            }.formStyle(.grouped)
            Divider()
            HStack {
                Text(notice ?? "完成后只保存连接配置；密钥始终留在钥匙串。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                Button("关闭", action: finish)
                Button("完成连接设置") {
                    do {
                        try request.exportApplied(model.appliedRecognitionConfiguration,
                            hasUnappliedChanges: model.hasUnappliedRecognitionSettings)
                        print("CONNECTION_SETUP_SAVED nonsecret_configuration_only; no provider requests")
                        finish()
                    } catch { notice = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
                    .disabled(model.applyingRecognitionSettings)
                    .accessibilityIdentifier("connectionSetup.finish")
            }.padding(20)
        }.frame(minWidth: 600, minHeight: 640)
            .foregroundStyle(Palette.ink).tint(Palette.green).background(Palette.paper)
    }
}
