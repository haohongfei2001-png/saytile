import SwiftUI
import SaytileKit

struct LocalModelSettings: View {
    @ObservedObject var model: AppModel
    @ViewState private var items: [LocalASRID: LocalModelStatus] = [:]
    @ViewState private var apple: SpeechAvailability?
    @ViewState private var readiness: SpeechAvailability?
    @ViewState private var readinessID: LocalASRID?
    @ViewState private var issue: String?
    @ViewState private var deletion: LocalASRID?
    @ViewState private var experiments: [LocalASRID] = []
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    var body: some View {
        if !model.completedFirstTranscript {
            Section("开始使用") {
                Text("Saytile 将讲话实时记成文字，原音和修改保存在这台 Mac。默认在本机识别，无需账号或 API。")
                Text("点击语音板右下角开始讲话，首次才会请求麦克风权限。自由记录和复制不需要辅助功能权限；需要直接输入到其他应用时，再到「输入与快捷键」授权。")
                    .font(.callout).foregroundStyle(.secondary)
                if model.microphoneDenied {
                    Button("打开麦克风权限设置…", action: model.openMicrophoneSettings)
                        .accessibilityIdentifier("models.firstUseMicrophone")
                    Text("未允许麦克风时，仍可打字、编辑和复制。允许后回到语音板即可开始。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    LabeledContent("麦克风", value: model.microphoneLabel)
                }
                Button("显示语音板", action: model.openPanel)
                    .accessibilityIdentifier("models.showVoicePanel")
            }.accessibilityIdentifier("models.firstUse")
        }
        Section("本机识别使用的模型") {
            if model.deviceOnly {
                LabeledContent("下一段本机识别", value: model.selectedLocalModel.title)
                    .accessibilityIdentifier("models.nextLocalEngine")
                if let readiness, readinessID == model.selectedLocalModel {
                    Text(readiness.installed ? "本机识别模型已就绪。" :
                        (model.audio.preparingAppleSpeech || items.values.contains(where: \.downloading)
                            ? "正在准备本机识别。资源就绪前，原音仍会保存，可稍后重新识别。"
                            : "本机识别尚未就绪。可继续下载或重新准备资源；已有原音和文字会保留。"))
                        .font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("models.readiness")
                }
            }
            if let fallback = model.localFallbackMessage {
                Text(fallback).font(.callout).foregroundStyle(.secondary)
            }
            if let last = model.lastASR {
                LabeledContent("最近一次实际识别", value: last)
                    .accessibilityIdentifier("models.lastActualEngine")
            }
            modelRow(LocalModelRecommendation.preferred)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Apple 中文识别").font(.body.weight(.medium))
                    Spacer()
                    choose(.apple, available: apple?.installed == true)
                }
                if model.audio.preparingAppleSpeech {
                    HStack { ProgressView().controlSize(.small); Text("正在准备中文资源…") }
                } else if let apple {
                    Text(apple.message).font(.caption).foregroundStyle(.secondary)
                }
                if let failure = model.audio.appleResourceFailure { Text(failure).font(.callout).foregroundStyle(.secondary) }
                if apple?.supported == true && apple?.installed == false {
                    Button(model.audio.appleResourceFailure == nil ? "下载中文资源" : "重新下载中文资源", action: model.prepareSpeech)
                        .disabled(model.audio.preparingAppleSpeech).controlSize(.small).accessibilityIdentifier("models.prepareApple")
                }
            }.padding(.vertical, 3)
                .task(id: model.audio.preparingAppleSpeech) {
                    guard !model.audio.preparingAppleSpeech else { return }
                    let result = await AppleSpeechService.availability()
                    if !Task.isCancelled { apple = result }
                }
            ForEach(LocalASRID.consumer.filter { $0 != .apple && $0 != LocalModelRecommendation.preferred }, id: \.rawValue) { id in
                modelRow(id)
            }
            if model.manualLocalModel != nil {
                Button("恢复默认模型") { model.selectLocal(nil) }
                    .controlSize(.small).accessibilityIdentifier("models.restoreDefault")
            }
            if let issue { Text(issue).foregroundStyle(.secondary) }
        }
        .task { await watchDirectory() }
        .confirmationDialog("删除这个模型的本机文件？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), presenting: deletion) { id in
            Button("删除模型", role: .destructive) { Task {
                do {
                    try await model.removeLocalModel(id)
                    experiments.removeAll { $0 == id }
                    issue = nil
                } catch { issue = error.localizedDescription }
            } }
        } message: { _ in Text("原音、文字和编辑版本会保留。需要时可以重新下载。") }
        if !experiments.isEmpty {
            Section {
                DisclosureGroup("清理旧模型文件") {
                    ForEach(experiments, id: \.self) { id in Button("删除 " + id.title + "…") { deletion = id } }
                }
            }
        }
    }

    private func modelRow(_ id: LocalASRID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(id.title).font(.body.weight(.medium))
                Spacer()
                if let status = items[id] {
                    if status.installed {
                        choose(id, available: true)
                    } else if status.downloading {
                        Button("暂停下载") { Task { await model.pauseLocalModelDownload(id) } }
                    } else {
                        Button(status.bytes > 0 ? "继续下载" : status.error != nil || status.diskBytes > 0 ? "重新下载" : "下载") {
                            Task { await model.downloadLocalModel(id) }
                        }
                    }
                }
            }.controlSize(.small)
            if let status = items[id] {
                if status.downloading || status.bytes > 0 && !status.installed {
                    ProgressView(value: Double(status.bytes), total: Double(max(1, status.total))).accessibilityLabel("下载进度")
                }
                HStack {
                    Text(status.installed ? "已安装 · " + size(status.diskBytes) :
                            (status.bytes > 0 ? size(status.bytes) + " / " : "下载大小 ") + size(status.total))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    if status.diskBytes > status.bytes && !status.installed {
                        Text("磁盘占用 " + size(status.diskBytes)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !status.downloading && status.diskBytes > 0 { Button("删除…") { deletion = id }.controlSize(.small) }
                }
                if let error = status.error { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                if id == LocalModelRecommendation.preferred && !status.installed {
                    Text("默认中文模型；只需下载一次，普通更新会保留。下载和准备不申请麦克风权限。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("正在读取本机文件…").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }

    @MainActor private func watchDirectory() async {
        experiments = await model.localModels.library.cachedExperimentalModels()
        repeat {
            for id in LocalASRID.consumer where id != .apple {
                let state = await model.localModels.library.status(id)
                guard !Task.isCancelled else { return }
                if items[id] != state { items[id] = state }
            }
            let selected = model.selectedLocalModel
            let available = await model.localModels.availability(selected)
            guard !Task.isCancelled else { return }
            if selected == model.selectedLocalModel { readiness = available; readinessID = selected }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        } while !Task.isCancelled
    }

    private func choose(_ id: LocalASRID, available: Bool) -> some View {
        let label = model.localModelChoiceLabel(id)
        return Button(label) { model.selectLocal(id) }
            .disabled(!available || model.isLocalChoiceFixed(id)).controlSize(.small)
            .accessibilityLabel(id.title + "，" + label)
            .accessibilityIdentifier("models.use." + id.rawValue)
    }
}
