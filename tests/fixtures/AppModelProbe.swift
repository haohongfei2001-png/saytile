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
        try await seed.close()
        let preferenceSuite = "app.saytile.test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: preferenceSuite)!
        defer { preferences.removePersistentDomain(forName: preferenceSuite) }
        preferences.set("synthetic-disconnected-microphone", forKey: "selectedDeviceUID")
        let model = try AppModel(directory: directory, preferences: preferences)
        try require(model.deviceID == UInt32.max && model.audio.selectedDeviceUID == "synthetic-disconnected-microphone", "missing remembered microphone never silently selects system default")
        model.deviceID = 0
        try require(model.audio.selectedDeviceUID == nil && preferences.string(forKey: "selectedDeviceUID") == nil, "explicit default device choice clears remembered hardware UID")
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
        // More than thirty new records must not silently disappear from the input panel.
        for index in 0..<115 {
            let row = try await model.store.createRecording(createdAt: Date().addingTimeInterval(Double(index) / 100))
            _ = try await model.store.saveEdit(recordingID: row.id, text: "连续表达第\(index)段")
            try await model.store.finishRecording(id: row.id)
        }
        await model.refresh()
        try require(model.panelCount == 116 && model.recent.count == 100 && model.panelHasMore, "panel exposes total and pagination instead of silently truncating after thirty")
        model.loadEarlierPanel()
        while model.loadingPanel { try await Task.sleep(for: .milliseconds(10)) }
        try require(model.recent.count == 116 && !model.panelHasMore, "earlier current-session expressions remain available for batch reuse")
        try require(model.recent.contains(where: { $0.id == new.id }), "earliest current-session expression survives prolonged input")
        // UI phase labels come from the same current-generation Store run state as production.
        let phaseRecord = try await model.store.createRecording(createdAt: Date().addingTimeInterval(60))
        try await model.store.finishRecording(id: phaseRecord.id)
        let phaseTicket = try await model.store.beginFusionRecognition(recordingID: phaseRecord.id, mode: .highestQuality)
        let phaseConfig = ModelConfiguration(purpose: .textFusion, provider: .openAIResponses, model: "synthetic-phase", cloudConsent: true)
        try await model.store.configureFusionRequirements(ticket: phaseTicket, configurations: [phaseConfig, .init(purpose: .chineseASR, provider: .qwenMessage, model: "synthetic-expert")])
        let phaseRun = try await model.store.beginModelRun(ticket: phaseTicket, configuration: phaseConfig)
        await model.refresh()
        guard let phaseItem = model.recent.first(where: { $0.id == phaseRecord.id }) else { throw Failure(message: "phase fixture not visible") }
        try require(model.recognitionPhaseLabel(for: phaseItem) == "正在核对文字", "production model exposes active text review without fabricated progress")
        try await model.store.finishModelRun(phaseRun)
        try await model.store.failRecognition(ticket: phaseTicket, message: "synthetic preserved failure")
        await model.refresh()
        guard let failedPhaseItem = model.recent.first(where: { $0.id == phaseRecord.id }) else { throw Failure(message: "failed phase fixture not visible") }
        try require(model.recognitionPhases[phaseRecord.id] == nil && model.recognitionPhaseLabel(for: failedPhaseItem) == "识别待恢复", "completed review phase disappears when logical recognition fails")
        model.updateEditorDraft("")
        await model.prepareForExit()
        try await model.store.close()
        let reopened = try SaytileStore(directory: directory)
        try require(try await reopened.loadDraft(recordingID: old.id) == "", "exit flush persists an intentionally empty unsaved draft")
        print("APP_MODEL_PROBE_PASS \(checks) checks; no microphone, no external input, no window activation")
    }
}
