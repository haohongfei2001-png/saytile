import AppKit
import SaytileKit

// Compiled together with the production AppModel.swift, using only isolated synthetic data.
@main
struct AppModelProbe {
    struct Failure: Error { let message: String }
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-model-probe-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var checks = 0
        func require(_ result: Bool, _ description: String) throws {
            guard result else { throw Failure(message: description) }
            checks += 1
            print("PASS " + description); fflush(nil)
        }
        let seed = try SaytileStore(directory: directory)
        let old = try await seed.createRecording(createdAt: .distantPast)
        try await seed.saveEdit(recordingID: old.id, text: "历史测试甲")
        try await seed.finishRecording(id: old.id)
        let other = try await seed.createRecording(createdAt: Date(timeIntervalSince1970: 1000))
        try await seed.saveEdit(recordingID: other.id, text: "历史测试乙")
        try await seed.finishRecording(id: other.id)
        let model = try AppModel(directory: directory)
        let first = Task { await model.initialLoad() }
        let second = Task { await model.initialLoad() }
        await first.value; await second.value
        try require(model.records.count == 2, "coalesced initial load waits for populated archive")
        try require(model.recent.isEmpty, "historical records do not enter current insertion panel")
        let oldRow = model.records.first { $0.id == old.id }!
        model.stageInPanel(oldRow, showPanel: false)
        await model.refresh()
        try require(model.recent.map(\.id) == [old.id], "only explicit historical reuse enters panel")
        model.clearPanel(); await model.refresh()
        try require(model.recent.isEmpty && model.records.count == 2, "clearing panel preserves archive")
        let new = try await model.store.createRecording()
        try await model.store.saveEdit(recordingID: new.id, text: "本次测试")
        try await model.store.finishRecording(id: new.id)
        await model.refresh()
        try require(model.recent.map(\.id) == [new.id], "new speech enters current session")
        try await model.store.setPinned(recordingID: old.id, pinned: true)
        model.recordFilter = .pinned
        await model.refresh()
        try require(model.records.map(\.id) == [old.id], "archive pinned filter reaches store")
        model.recordFilter = .all; model.query = "历史测试乙"
        await model.refresh()
        try require(model.records.map(\.id) == [other.id], "archive search reaches store without mixing pages")
        let cleanup = await model.previewCleanup()
        try require(!cleanup && model.cleanupCount == 0, "cleanup preview waits for candidates and protects unrecognized audio")
        model.query = ""; await model.refresh()
        let firstEditor = model.records.first { $0.id == old.id }!
        let secondEditor = model.records.first { $0.id == other.id }!
        await model.selectForEditing(firstEditor)
        model.updateEditorDraft("未保存的修改😀")
        await model.selectForEditing(secondEditor)
        try require(try await model.store.loadDraft(recordingID: old.id) == "未保存的修改😀", "switching records flushes pending draft without waiting for debounce")
        try require(model.editorDraft == secondEditor.text, "switching records does not show another record's draft")
        await model.selectForEditing(firstEditor)
        try require(model.editorDraft == "未保存的修改😀", "returning to record restores durable unsaved draft")
        await model.refresh(); await model.refresh()
        try require(model.editorDraft == "未保存的修改😀", "periodic refresh does not reset unsaved editor text")
        model.updateEditorDraft("正式修改版本")
        await model.saveEditorChanges()
        try require(try await model.store.recording(id: old.id)?.text == "正式修改版本", "save modification creates selected immutable version")
        try require(try await model.store.loadDraft(recordingID: old.id) == nil, "successful version save clears old editor draft")
        model.updateEditorDraft("版本保存期间的旧草稿")
        let saving = Task { await model.saveEditorChanges() }
        await Task.yield()
        model.updateEditorDraft("版本保存期间的新输入")
        await saving.value
        _ = await model.flushEditorDrafts()
        let savedText = try await model.store.recording(id: old.id)?.text
        let savedDraft = try await model.store.loadDraft(recordingID: old.id)
        try require(savedText == "版本保存期间的新输入" || savedDraft == "版本保存期间的新输入", "typing during version commit is retained as version or newer draft")
        model.updateEditorDraft("")
        await model.prepareForExit()
        let reopened = try SaytileStore(directory: directory)
        try require(try await reopened.loadDraft(recordingID: old.id) == "", "exit flush persists an intentionally empty unsaved draft")
        print("APP_MODEL_PROBE_PASS \(checks) checks; no microphone, no external input, no window activation")
    }
}
