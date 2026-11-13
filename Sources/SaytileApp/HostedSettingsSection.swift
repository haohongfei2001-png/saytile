import SwiftUI
import AppKit
import SaytileKit

struct HostedSettingsSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var account: HostedAccount
    @ViewState private var email = ""
    @ViewState private var code = ""
    @FocusState private var focus: Field?
    private enum Field { case email, code }

    var body: some View {
        Section("账户") {
            LabeledContent("登录状态", value: account.status)
            if account.signedIn {
                if let plan = account.plan { LabeledContent("套餐", value: plan) }
                if let ms = account.remainingMS {
                    LabeledContent("可用时长", value: "\(ms / 60000) 分 \(ms % 60000 / 1000) 秒")
                }
                if let end = account.validUntil { LabeledContent("有效期至", value: String(end.prefix(10))) }
                HStack {
                    Button("刷新权益") { Task { await account.refresh() } }
                    if account.billingAvailable {
                        Button("开通订阅") { Task { if let url = await account.billingURL(portal: false) { NSWorkspace.shared.open(url) } } }
                        Button("管理订阅") { Task { if let url = await account.billingURL(portal: true) { NSWorkspace.shared.open(url) } } }
                    }
                    Button("退出登录") {
                        if account.selected { model.allowHostedSpeech(false) }
                        Task { await account.signOut() }
                    }
                }.disabled(account.busy)
            } else {
                TextField("电子邮箱", text: $email).textContentType(.emailAddress).focused($focus, equals: .email)
                    .accessibilityLabel("电子邮箱").accessibilityIdentifier("hosted.email")
                Button("获取验证码") { Task { await account.sendCode(email: email); focus = .code } }
                    .disabled(account.busy || !email.contains("@"))
                SecureField("邮件验证码", text: $code).textContentType(.oneTimeCode).focused($focus, equals: .code)
                    .accessibilityLabel("邮件验证码").accessibilityIdentifier("hosted.code")
                Button("登录") { Task { await account.verify(email: email, code: code); if account.signedIn { code = "" } } }
                    .disabled(account.busy || code.isEmpty || email.isEmpty)
                if account.busy { ProgressView().controlSize(.small).accessibilityLabel("正在连接账户") }
            }
        }.onAppear { account.displaySavedAccount() }
        Section("语音授权") {
            Toggle("允许将新讲话交给云端中文识别", isOn: Binding(
                get: { !model.deviceOnly && account.selected && account.consent }, set: model.allowHostedSpeech))
                .accessibilityIdentifier("hosted.upload-consent")
            Text("新讲话经 Saytile 发送到阿里云识别，文字交给 OpenAI 核对。关闭后使用本机识别，历史原音保留在本机。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
