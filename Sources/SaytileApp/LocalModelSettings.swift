import SwiftUI
import SaytileKit

struct LocalModelSettings: View {
    @ObservedObject var model: AppModel
    @ViewState private var items: [LocalASRID: LocalModelStatus] = [:]
    @ViewState private var apple: SpeechAvailability?
    @ViewState private var issue: String?
    @ViewState private var deletion: LocalASRID?
    @ViewState private var experiments: [LocalASRID] = []
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    var body: some View {
        Section("本机识别使用的模型") {
            if let fallback = model.localFallbackMessage {
                Text(fallback).font(.callout).foregroundStyle(.secondary)
            }
            if let last = model.lastASR {
                LabeledContent("最近一次实际识别", value: last)
                    .accessibilityIdentifier("models.lastActualEngine")
            }
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
            ForEach(LocalASRID.consumer.filter { $0 != .apple }, id: \.rawValue) { id in
                modelRow(id)
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
        Section {
            DisclosureGroup("运行内存参考") {
                Text("M5 实测 App 与助手的同时峰值为 Paraformer 509 MiB、Qwen 1,442 MiB。Apple 的共享系统服务无法单独计量。实际占用随讲话时长变化。")
                    .font(.callout).foregroundStyle(.secondary)
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
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        } while !Task.isCancelled
    }

    private func choose(_ id: LocalASRID, available: Bool) -> some View {
        let selected = model.selectedLocalModel == id
        return Button(selected ? "已选择" : "使用此模型") { model.selectLocal(id) }
            .disabled(selected || !available).controlSize(.small)
            .accessibilityLabel(id.title + (selected ? "，已选择" : "，使用此模型"))
            .accessibilityIdentifier("models.use." + id.rawValue)
    }
}
