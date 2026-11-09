import SwiftUI
import AppKit
import SaytileKit

struct HostedSettingsSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var account: HostedAccount
    @ViewState private var email = ""
    @ViewState private var code = ""
    var body: some View {
        Section("识别服务") {
            Picker("服务来源", selection: Binding(get:{model.deviceOnly ? "local" : account.selected ? "hosted" : "byok"},set:{model.selectSource($0)})) {
                Text("本机").tag("local")
                Text("Saytile Cloud").tag("hosted")
                Text("自带 API").tag("byok")
            }.pickerStyle(.segmented)
            if account.selected {
                LabeledContent("账户状态",value:account.status)
                if !account.signedIn {
                    TextField("电子邮箱",text:$email).textContentType(.emailAddress).accessibilityLabel("电子邮箱").accessibilityIdentifier("hosted.email")
                    HStack {
                        SecureField("邮件验证码",text:$code).accessibilityLabel("邮件验证码").accessibilityIdentifier("hosted.code")
                        Button("获取验证码") {Task {await account.sendCode(email:email)}}.disabled(account.busy || !email.contains("@"))
                        Button("登录") {Task { await account.verify(email:email,code:code);code="" }}.disabled(account.busy || code.isEmpty || email.isEmpty)
                    }
                } else {
                    if let plan=account.plan {LabeledContent("套餐",value:plan)}
                    if let ms=account.remainingMS {LabeledContent("可用时长",value:"\(ms / 60000) 分 \(ms % 60000 / 1000) 秒")}
                    if let end=account.validUntil { LabeledContent("有效期至",value:String(end.prefix(10))) }
                    HStack {
                        Button("刷新权益") {Task {await account.refresh()}}
                        if account.billingAvailable {
                        Button("开通订阅") {Task {if let url=await account.billingURL(portal:false){NSWorkspace.shared.open(url)}}}
                        Button("管理订阅") {Task {if let url=await account.billingURL(portal:true){NSWorkspace.shared.open(url)}}}
                        }
                        Button("退出") {Task {await account.signOut()}}
                    }.disabled(account.busy)
                }
                Toggle("允许将新讲话交给云端中文识别",isOn:Binding(get:{account.consent},set:{account.authorize($0)}))
                    .accessibilityLabel("允许将新讲话交给云端中文识别").accessibilityIdentifier("hosted.upload-consent")
                Text("开启后，新语音经 Saytile 转交阿里云识别，候选文字交 OpenAI 核对。关闭后使用本机识别。历史原音不会自动上传。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
