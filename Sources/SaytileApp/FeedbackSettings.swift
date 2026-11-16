import SwiftUI
import RiftletFeedback

struct FeedbackSettings: View {
    @ObservedObject var model: FeedbackSettingsModel
    @ViewState private var withdrawing: FeedbackRecord?
    var body: some View {
        Section {
            Picker("类型", selection: Binding(get: { model.draft.kind }, set: { model.edit(kind: $0) })) {
                Text("遇到问题").tag(FeedbackKind.problem)
                Text("建议").tag(FeedbackKind.suggestion)
            }.pickerStyle(.segmented).disabled(!model.ready || model.busy || model.closing).accessibilityIdentifier("feedback.kind")
            TextEditor(text: Binding(get: { model.draft.text }, set: { model.edit(text: $0) }))
                .font(.body).frame(minHeight: 140).disabled(!model.ready || model.busy || model.closing)
                .accessibilityLabel("反馈内容").accessibilityIdentifier("feedback.text")
            HStack {
                Text("\(model.draft.text.unicodeScalars.count) / 4000").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.busy ? "正在保存…" : "发送反馈", action: model.send)
                    .disabled(!model.canSend).accessibilityIdentifier("feedback.send")
            }
            Text("反馈发送到开发者的私有反馈中心，并标记为 Saytile。只提交你填写的内容、产品版本和提交时间；不会附带录音、转写文字或日志。")
                .font(.callout).foregroundStyle(.secondary)
            if let message = model.message { Text(message).font(.callout).textSelection(.enabled).accessibilityIdentifier("feedback.message") }
        }.task {
            while !Task.isCancelled {
                await model.reload()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        if !model.records.isEmpty {
            Section("我的反馈") {
                ForEach(model.records, id: \.id) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(record.envelope.kind == .problem ? "遇到问题" : "建议").font(.headline)
                            Spacer()
                            Text(record.created, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(record.envelope.text).textSelection(.enabled)
                        HStack {
                            Text(status(record.state)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if record.state == .cancelled || record.state == .deleted {
                                Button("移除本机记录") { Task { await model.forget(record) } }
                            } else {
                                Button("刷新状态") { Task { await model.refresh(record) } }
                                if ![.deletionQueued, .deletionPending].contains(record.state) {
                                    Button(record.state == .deletionBlocked ? "重试撤回" : "撤回") { withdrawing = record }
                                }
                            }
                        }
                    }.padding(.vertical, 4).disabled(model.closing)
                }
            }
        }
        Section {
            Text("未发送的反馈可在本机取消。已发送的反馈可申请删除；只有服务确认后才显示已删除。请勿填写密码或其他敏感资料。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("撤回这条反馈？", isPresented: Binding(get: { withdrawing != nil }, set: { if !$0 { withdrawing = nil } })) {
            Button("撤回反馈", role: .destructive) { if let value = withdrawing { Task { await model.withdraw(value) } }; withdrawing = nil }
        } message: { Text("未发送的内容会停止投递；已发送的内容将申请从反馈中心删除。") }
    }
    private func status(_ state: FeedbackLocalState) -> String {
        switch state {
        case .queued: "等待发送，已保存在本机"
        case .received: "已收到，正在转交开发者"
        case .delivered: "已送达开发者"
        case .blocked: "暂时无法发送，内容已保留"
        case .cancelled: "已取消，未发送"
        case .deletionQueued: "撤回申请等待发送"
        case .deletionBlocked: "撤回暂时受阻，请稍后重试"
        case .deletionPending: "正在处理撤回"
        case .deleted: "已确认删除"
        case .expired: "发送已过期，本机内容仍保留"
        }
    }

}
