import SwiftUI
import SaytileKit

struct LocalModelSettings: View {
    @ObservedObject var model: AppModel
    @ViewState private var manual = false
    @ViewState private var items: [LocalASRID: LocalModelStatus] = [:]
    @ViewState private var issue: String?
    @ViewState private var deletion: LocalASRID?
    @ViewState private var experiments: [LocalASRID] = []
    private var directory: Bool { manual || model.manualLocalModel != nil || model.archiveLocalModel != nil }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    var body: some View {
        Group {
        Section("识别方式") {
            Picker("模型选择", selection: Binding(get: { directory }, set: { value in
                manual = value
                if !value { model.selectLocal(nil); model.selectLocal(nil, archiveOnly: true) }
            })) { Text("自动推荐").tag(false); Text("手动选择").tag(true) }
                .pickerStyle(.segmented).accessibilityIdentifier("models.mode")
                .task(id: directory) { await watchDirectory() }
                .confirmationDialog("删除这个模型的本机文件？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), presenting: deletion) { id in
            Button("删除模型", role: .destructive) { Task {
                do {
                    try await model.localModels.delete(id)
                    if model.manualLocalModel == id { model.selectLocal(nil) }; if model.archiveLocalModel == id { model.selectLocal(nil, archiveOnly: true) }
                    issue = nil
                } catch { issue = error.localizedDescription }
            } }
        } message: { _ in Text("原音、文字和编辑版本会保留。需要时可以重新下载。") }
            if !directory { Text("优先使用 Apple 中文识别。本机资源不可用时，可选轻量模型。").font(.callout).foregroundStyle(.secondary) }
        }
        Section("Apple 中文识别") {
            LabeledContent("语言资源", value: model.audio.preparingAppleSpeech ? "正在准备…" : model.engineLabel)
            if let failure = model.audio.appleResourceFailure { Text(failure).font(.callout).foregroundStyle(.secondary) }
            HStack {
                if model.audio.preparingAppleSpeech { ProgressView().controlSize(.small) }
                Button(model.audio.appleResourceFailure == nil ? "准备系统语言资源" : "重新准备语言资源", action: model.prepareSpeech)
                    .disabled(model.audio.preparingAppleSpeech).accessibilityIdentifier("models.prepareApple")
                if directory { choose(.apple) }
            }
        }
        Section(directory ? "可用模型" : "可选轻量模型") {
            ForEach(directory ? LocalASRID.consumer.filter { $0 != .apple } : [.sherpa], id: \.rawValue) { id in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(id == .sherpa ? "Streaming Paraformer" : id == .qwen ? "Qwen3-ASR 0.6B" : id.title).font(.body.weight(.medium))
                        Spacer(); if let state = items[id] { Text(state.installed ? "已安装" : state.downloading ? "正在下载" : state.bytes > 0 ? "已暂停" : "未安装").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let status = items[id] {
                        if status.downloading || status.bytes > 0 && !status.installed {
                            ProgressView(value: Double(status.bytes), total: Double(max(1, status.total)))
                                .accessibilityLabel("下载进度")
                        }
                        Text(status.installed ? "磁盘占用 \(size(status.diskBytes))" : "\(size(status.bytes)) / \(size(status.total))" + (status.diskBytes > status.bytes ? " · 磁盘占用 \(size(status.diskBytes))" : ""))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        if let error = status.error { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                        HStack {
                            if status.installed { if directory { choose(id) } }
                            else if status.downloading { Button("暂停下载") { Task { await model.localModels.library.pause(id) } } }
                            else { Button(status.bytes > 0 ? "继续下载" : status.error != nil || status.diskBytes > 0 ? "重新下载" : "下载模型") { Task { await model.localModels.library.download(id) } } }
                            if !status.downloading && status.diskBytes > 0 { Button("删除…") { deletion = id } }
                        }.controlSize(.small)
                    } else { Text("正在读取本机文件…").font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 3)
            }
            if directory {
                DisclosureGroup("运行内存参考") {
                    Text("M5 实测 App 与助手的同时峰值：Paraformer 509 MiB，Qwen 1,442 MiB。Apple 的共享系统服务无法单独计量。实际占用随讲话时长变化。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !experiments.isEmpty {
                    DisclosureGroup("清理旧模型文件") { ForEach(Array(experiments.enumerated()), id: \.element.rawValue) { index, id in Button("删除旧资源 " + String(index + 1) + "…") { deletion = id } } }
                }
            }
            if let issue { Text(issue).foregroundStyle(.secondary) }
        }
        if model.deviceOnly {
            Section("可选文字核对") {
                Toggle("用 GPT-6 核对新讲话的文字", isOn: Binding(get: { model.localTextAllowed }, set: { model.allowLocalText($0) }))
                    .disabled(!model.localTextAllowed && model.localGPT.map(model.hasCredential) != true)
                Text("需在自带 API 中保存密钥。开启后仅发送文字，费用由服务商计收。").font(.callout).foregroundStyle(.secondary)
            }
        }
        }
    }
    @MainActor private func watchDirectory() async {
            repeat {
                let previous = items[.sherpa]?.installed
                for id in (directory ? LocalASRID.consumer : [.sherpa]) where id != .apple {
                    let state = await model.localModels.library.status(id)
                    if items[id] != state { items[id] = state }
                }
                if directory { let cached = await model.localModels.library.cachedExperimentalModels(); if cached != experiments { experiments = cached } }
                if previous != items[.sherpa]?.installed { await model.refreshLocalRecommendation() }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            } while !Task.isCancelled
    }
    private func choose(_ id: LocalASRID) -> some View {
        Button(model.manualLocalModel == id ? "已用于新讲话" : "用于新讲话") { model.selectLocal(id) }
            .disabled(model.manualLocalModel == id).controlSize(.small)
    }
}
