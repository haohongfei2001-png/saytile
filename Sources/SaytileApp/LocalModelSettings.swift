import SwiftUI
import SaytileKit

struct LocalModelSettings: View {
    @ObservedObject var model: AppModel
    @ViewState private var manual = false
    @ViewState private var items: [LocalASRID: LocalModelStatus] = [:]
    @ViewState private var issue: String?
    var body: some View {
        Section("本机识别") {
            Picker("模型选择", selection: Binding(get: { manual || model.manualLocalModel != nil || model.archiveLocalModel != nil },
                set: { value in manual = value; if !value { model.selectLocal(nil); model.selectLocal(nil, archiveOnly: true) } })) {
                Text("自动推荐").tag(false)
                Text("手动选择").tag(true)
            }.pickerStyle(.segmented)
            if manual || model.manualLocalModel != nil || model.archiveLocalModel != nil {
                ForEach(LocalASRID.allCases, id: \.rawValue) { id in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(id.title)
                            Spacer()
                            control(id)
                        }
                        Text(detail(id)).font(.caption).foregroundStyle(.secondary)
                        if let error = items[id]?.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } else {
                Text(LocalModelRecommendation.description).font(.callout).foregroundStyle(.secondary)
                if items[.sherpa]?.installed == false {
                    if items[.sherpa]?.downloading == true {
                        Button("暂停下载") { Task { await model.localModels.library.pause(.sherpa) } }
                    } else {
                        Button("准备轻量模型（237 MB）") { Task { await model.localModels.library.download(.sherpa) } }
                    }
                }
            }
            if model.deviceOnly {
                Toggle("允许 GPT-6 核对新录音的文字", isOn: Binding(get: { model.localTextAllowed }, set: { model.allowLocalText($0) }))
                    .disabled(!model.localTextAllowed && model.localGPT.map(model.hasCredential) != true)
                Text("使用自带 API 中的 GPT-6 密钥，只发送本段识别文字。").font(.caption).foregroundStyle(.secondary)
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
        }.task {
            repeat {
                let previous = items[.sherpa]?.installed
                for id in LocalASRID.allCases where id != .apple { items[id] = await model.localModels.library.status(id) }
                if items[.sherpa]?.installed != previous { await model.refreshLocalRecommendation() }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            } while !Task.isCancelled
        }
    }
    private func detail(_ id: LocalASRID) -> String {
        if id == .apple { return "系统管理中文资源 · 实时识别" }
        let status = items[id]
        let format: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let type = id.capability == .batch ? "分段重识别" : id.capability == .chunked ? "分块增量" : "流式识别"
        return "\(type) · \(format(status?.bytes ?? 0)) / \(format(status?.total ?? 0))"
    }
    @ViewBuilder private func control(_ id: LocalASRID) -> some View {
        if id == .apple || items[id]?.installed == true {
            if id.capability == .batch {
                Button(model.archiveLocalModel == id ? "已选重识别" : "用于重识别") { model.selectLocal(id, archiveOnly: true) }
            } else {
                Button(model.manualLocalModel == id ? "已选新讲话" : "用于新讲话") { model.selectLocal(id) }
            }
            if id != .apple {
                Button("删除") {
                    Task { do {
                        try await model.localModels.delete(id)
                        if model.manualLocalModel == id { model.selectLocal(nil) }
                        if model.archiveLocalModel == id { model.selectLocal(nil, archiveOnly: true) }
                    } catch { issue = error.localizedDescription } }
                }
            }
        } else if items[id]?.downloading == true {
            Button("暂停") { Task { await model.localModels.library.pause(id) } }
        } else {
            Button((items[id]?.bytes ?? 0) > 0 ? "继续下载" : "下载") { Task { await model.localModels.library.download(id) } }
        }
    }
}
