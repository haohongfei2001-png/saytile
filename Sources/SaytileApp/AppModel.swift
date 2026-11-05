import AppKit
import SwiftUI
import Combine
import ServiceManagement
import AVFoundation
import SaytileKit

struct DisplayRecording: Identifiable, Equatable {
    let source: Recording
    var id: UUID { source.id }
    var text: String { source.text }
    var date: Date { source.createdAt }
    var pinned: Bool { source.isPinned }
    var hasAudio: Bool { source.audioState == .available && source.duration > 0 }
    var isRecording: Bool { source.isRecording }
    var needsRecovery: Bool { source.recognitionState == .failed || source.recognitionState == .queued }
    var stateLabel: String {
        if source.isRecording { return "正在记录" }
        switch source.recognitionState {
        case .queued: return "等待识别"
        case .running: return "正在识别"
        case .completed: return "文字已保存"
        case .failed: return "识别待恢复"
        case .cancelled: return "文字已保留"
        }
    }
    var audioLabel: String {
        switch source.audioState {
        case .available: return source.duration > 0 ? "原音 · \(Int(source.duration)) 秒" : "原音保存中"
        case .deleted: return "原音已删除 · 文字保留"
        case .deletePending: return "原音清理中"
        case .missing: return "原音文件缺失"
        }
    }
}
struct DisplayVersion: Identifiable {
    let id: UUID
    let text: String
    let label: String
}
struct DisplayDevice: Identifiable { let id: UInt32; let name: String }

@MainActor
final class AppModel: ObservableObject {
    let store: SaytileStore
    let audio: AudioController
    let input: NativeInputCoordinator
    let directory: URL
    @Published var recent: [DisplayRecording] = []
    @Published var records: [DisplayRecording] = []
    @Published var versions: [DisplayVersion] = []
    @Published var selected: DisplayRecording?
    @Published private(set) var editorDraft = ""
    @Published private(set) var editorDraftLoading = false
    @Published private(set) var savingEditorChanges = false
    @Published private(set) var editorDraftStatus = "草稿自动保留，保存修改创建版本"
    @Published var recordFilter: RecordingFilter = .all { didSet { pageLimit = 100; scheduleRefresh() } }
    @Published var query = "" { didSet { pageLimit = 100; scheduleRefresh() } }
    @Published var notice: String?
    @Published var directMode = false
    @Published var targetLabel = "在目标草稿中放置光标，再绑定"
    @Published var hasStarted = false
    @Published var storageLabel = "计算中…"
    @Published var cleanupCount = 0
    @Published private(set) var preparingCleanup = false
    @Published private(set) var isInserting = false
    @Published var deviceID: UInt32 = 0 { didSet { audio.selectedDeviceID = deviceID } }
    @Published var shortcutChoice = UserDefaults.standard.string(forKey: "shortcutChoice") ?? "option-space" {
        didSet { UserDefaults.standard.set(shortcutChoice, forKey: "shortcutChoice"); NotificationCenter.default.post(name: .init("SaytileShortcutChanged"), object: nil) }
    }
    @Published var launchAtLogin = false { didSet { setLoginItem() } }
    @Published var hasMore = false
    var openPanel: () -> Void = {}
    var hidePanel: () -> Void = {}
    var openArchive: () -> Void = {}
    var openSettings: () -> Void = {}
    private var pageLimit = 100
    private var timer: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var directRevisions: Set<UUID> = []
    private var cleanupIDs: [UUID] = []
    private var refreshOperation: Task<Void, Never>?
    private var initializing = true
    private var captureWasEnabled = false
    private var lastStorageRefresh = Date.distantPast
    private var recovered = false
    private var recoveryTask: Task<Void, Never>?
    private var panelSessionStartedAt = Date()
    private var stagedRecordIDs: Set<UUID> = []
    private struct DraftWrite: Equatable { let sequence: UInt64; let text: String }
    private var editorRecordingID: UUID?
    private var editorWasEdited = false
    private var editorSelectionGeneration = UUID()
    private var draftSequence: UInt64 = 0
    private var pendingDraftWrites: [UUID: DraftWrite] = [:]
    private var latestEditorValues: [UUID: DraftWrite] = [:]
    private var committingEditorIDs: Set<UUID> = []
    private var editorDebounce: Task<Void, Never>?
    private var editorFlushTask: Task<Bool, Never>?
    private var editorFlushGeneration: UInt64 = 0
    var editorCanEdit: Bool { editorRecordingID != nil && !editorDraftLoading }
    var hasUnpersistedDrafts: Bool { !pendingDraftWrites.isEmpty }

    init(directory: URL) throws {
        self.directory = directory
        store = try SaytileStore(directory: directory)
        audio = AudioController(store: store)
        input = NativeInputCoordinator(store: store)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        initializing = false
        input.onBindingInvalidated = { [weak self] in
            self?.directMode = false
            self?.targetLabel = "目标已改变，请重新绑定草稿"
            self?.notice = "自动输入已暂停，新内容继续保留在 Saytile。"
        }
        subscription = audio.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            do { _ = try await AudioDiagnostics.recoverAudio(store: store); recovered = true }
            catch { notice = "资料恢复尚未完成：\(error.localizedDescription)" }
        }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    var isListening: Bool {
        switch audio.state { case .listening, .speaking, .starting: return true; default: return false }
    }
    var captureLabel: String {
        switch audio.state {
        case .paused: return "已暂停"
        case .starting: return "正在准备"
        case .listening: return "持续待命"
        case .speaking: return "正在听"
        case .interrupted(let reason): return reason
        }
    }
    var captureProblem: Bool { if case .interrupted = audio.state { return true }; return false }
    var saveLabel: String { isListening ? "原音独立保存 · 识别不会阻塞收音" : "内容保存在此 Mac，随时可以取用" }
    var microphoneLabel: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "已允许"
        case .notDetermined: return "开启收音时请求"
        default: return "未允许，请在系统设置中开启"
        }
    }
    var accessibilityLabel: String { input.hasPermission ? "已允许" : "尚未允许 · 可正常复制" }
    var engineLabel: String { audio.speechStatus }
    var devices: [DisplayDevice] { [DisplayDevice(id: 0, name: "系统默认输入设备")] + audio.devices.map { DisplayDevice(id: $0.id, name: $0.name) } }
    var playingID: UUID? { audio.playingID }
    func toggleCapture() {
        Task {
            await recoveryTask?.value
            guard recovered else { notice = "资料库恢复未完成，请先重新打开 Saytile。已有资料会保留。"; return }
            if isListening { captureWasEnabled = false; await audio.pause() }
            else { hasStarted = true; captureWasEnabled = true; await audio.start() }
            if let issue = audio.issue { notice = issue }
        }
    }
    func setDirect(_ enabled: Bool) {
        directMode = enabled
        if !enabled { input.invalidate(); targetLabel = "在目标草稿中放置光标，再绑定" }
    }
    func bindTarget() {
        Task {
            do { let binding = try await input.bindCurrentTarget(); directMode = true; targetLabel = binding.label; directRevisions.removeAll() }
            catch { notice = error.localizedDescription }
        }
    }
    func copy(_ text: String) { input.copy(text); notice = "已复制，可以粘贴到任何应用。" }
    func copyRecent() { copy(recent.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")) }
    func insertRecent() {
        guard !isInserting else { return }
        // Freeze immutable revision identifiers at the user's click, before any await.
        let snapshots = recent.filter { !$0.text.isEmpty }.compactMap { item in
            item.source.preferredRevisionID.map { (recordingID: item.id, revisionID: $0, text: item.text) }
        }
        guard !snapshots.isEmpty else { return }
        isInserting = true
        Task {
            defer { isInserting = false }
            do {
                _ = try await input.bindCurrentTarget()
                var frozen: [TranscriptRevision] = []
                for snapshot in snapshots {
                    frozen.append(try await store.freezeRevision(recordingID: snapshot.recordingID, revisionID: snapshot.revisionID, text: snapshot.text))
                }
                for snapshot in frozen {
                    let result = await input.insert(recordingID: snapshot.recordingID, revisionID: snapshot.id)
                    notice = result.message
                    // A batch is a single user action. Do not continue sending following records
                    // after an uncertain/failed attempt; a new action can explicitly reuse them.
                    guard result == .confirmed else { return }
                }
            } catch { notice = error.localizedDescription }
        }
    }
    func clearPanel() {
        guard !isInserting else { return }
        panelSessionStartedAt = Date()
        stagedRecordIDs.removeAll()
        recent = []
        notice = "输入板已清空，全部记录仍在语音档案中。"
    }
    func stageInPanel(_ item: DisplayRecording, showPanel: Bool = true) {
        stagedRecordIDs.insert(item.id)
        if !recent.contains(where: { $0.id == item.id }) { recent.append(item); recent.sort { $0.date < $1.date } }
        if showPanel { openPanel() }
        notice = "已带到输入板，可与本次表达一起复制或插入。"
    }
    func select(_ item: DisplayRecording) {
        openArchive()
        Task { await selectForEditing(item) }
    }
    func prepareEditorIfNeeded(_ item: DisplayRecording) async {
        guard editorRecordingID != item.id, !(editorDraftLoading && selected?.id == item.id) else { return }
        await selectForEditing(item)
    }
    func selectForEditing(_ item: DisplayRecording) async {
        if editorRecordingID == item.id { selected = item; await loadVersions(item.id); return }
        editorDebounce?.cancel()
        let generation = UUID(); editorSelectionGeneration = generation
        selected = item; versions = []; editorDraftLoading = true; editorRecordingID = nil; editorDraft = ""
        _ = await flushEditorDrafts()
        do {
            let stored = try await store.loadDraft(recordingID: item.id)
            guard let current = try await store.recording(id: item.id) else { return }
            guard editorSelectionGeneration == generation, selected?.id == item.id else { return }
            let draft = pendingDraftWrites[item.id]?.text ?? stored
            editorDraft = draft ?? current.text
            editorWasEdited = draft != nil
            editorRecordingID = item.id; editorDraftLoading = false
            editorDraftStatus = pendingDraftWrites[item.id] == nil ? "草稿自动保留，保存修改创建版本" : "草稿尚未写入磁盘，请保留此窗口"
            await loadVersions(item.id)
        } catch {
            if editorSelectionGeneration == generation { editorDraftStatus = "草稿读取失败，请重新选择记录"; notice = error.localizedDescription; editorDraftLoading = false }
        }
    }
    func closeDetail() {
        editorSelectionGeneration = UUID(); selected = nil; editorRecordingID = nil
        editorDebounce?.cancel()
        Task { _ = await flushEditorDrafts() }
    }
    func updateEditorDraft(_ text: String) {
        guard let id = editorRecordingID, !editorDraftLoading else { return }
        editorDraft = text; editorWasEdited = true; draftSequence &+= 1
        let write = DraftWrite(sequence: draftSequence, text: text)
        pendingDraftWrites[id] = write; latestEditorValues[id] = write
        editorDraftStatus = "正在保留草稿…"
        editorDebounce?.cancel()
        editorDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            _ = await self?.flushEditorDrafts()
        }
    }
    @discardableResult func flushEditorDrafts() async -> Bool {
        if let editorFlushTask {
            let generation = editorFlushGeneration
            let saved = await editorFlushTask.value
            if editorFlushGeneration == generation { self.editorFlushTask = nil }
            guard saved else { return false }
            return await flushEditorDrafts()
        }
        guard pendingDraftWrites.contains(where: { !committingEditorIDs.contains($0.key) }) else { return pendingDraftWrites.isEmpty }
        editorFlushGeneration &+= 1
        let generation = editorFlushGeneration
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return true }
            while let (id, write) = self.pendingDraftWrites.first(where: { !self.committingEditorIDs.contains($0.key) }) {
                do {
                    try await self.store.saveDraft(recordingID: id, text: write.text)
                    if self.pendingDraftWrites[id] == write { self.pendingDraftWrites.removeValue(forKey: id) }
                    if self.editorRecordingID != id, !self.committingEditorIDs.contains(id), self.pendingDraftWrites[id] == nil { self.latestEditorValues.removeValue(forKey: id) }
                    if self.editorRecordingID == id, self.pendingDraftWrites[id] == nil {
                        self.editorDraftStatus = "草稿已自动保留，保存修改创建版本"
                    }
                } catch StoreError.missingRecording {
                    // A deliberate record deletion also cancels a queued draft write.
                    self.pendingDraftWrites.removeValue(forKey: id); self.latestEditorValues.removeValue(forKey: id)
                } catch {
                    self.editorDraftStatus = "草稿尚未写入磁盘，请勿退出"
                    self.notice = "草稿保存失败：\(error.localizedDescription)"
                    return false
                }
            }
            return true
        }
        editorFlushTask = task
        let saved = await task.value
        if editorFlushGeneration == generation { editorFlushTask = nil }
        guard saved else { return false }
        return await flushEditorDrafts()
    }
    func saveEditorChanges() async {
        guard let item = selected, editorRecordingID == item.id, !editorDraftLoading, !savingEditorChanges else { return }
        let text = editorDraft, sequence = latestEditorValues[item.id]?.sequence
        savingEditorChanges = true; committingEditorIDs.insert(item.id); editorDebounce?.cancel()
        // Let a previously issued draft write finish before saveEdit atomically clears it.
        _ = await editorFlushTask?.value
        do {
            _ = try await store.saveEdit(recordingID: item.id, text: text)
            if latestEditorValues[item.id]?.sequence == sequence {
                pendingDraftWrites.removeValue(forKey: item.id)
                if editorRecordingID == item.id { editorWasEdited = false; editorDraftStatus = "修改已保存为新版本" }
            } else if let newer = latestEditorValues[item.id] {
                // Typing while a version is committed remains a separate unsaved draft.
                pendingDraftWrites[item.id] = newer
            }
        } catch { notice = error.localizedDescription }
        committingEditorIDs.remove(item.id); savingEditorChanges = false
        _ = await flushEditorDrafts()
        await refresh(); await loadVersions(item.id)
    }
    func pin(_ item: DisplayRecording) { perform { try await self.store.setPinned(recordingID: item.id, pinned: !item.pinned); await self.refresh() } }
    func retry(_ item: DisplayRecording) { Task { await audio.retry(recordingID: item.id); await refresh() } }
    func play(_ item: DisplayRecording) {
        perform {
            if self.audio.playingID == item.id { self.audio.stopPlayback() }
            else { try await self.audio.play(recordingID: item.id) }
        }
    }
    func eraseAudio(_ item: DisplayRecording) { perform { try await self.store.deleteAudio(recordingID: item.id); await self.refresh() } }
    func deleteRecord(_ item: DisplayRecording) {
        perform {
            try await self.store.deleteRecord(recordingID: item.id)
            self.pendingDraftWrites.removeValue(forKey: item.id); self.latestEditorValues.removeValue(forKey: item.id)
            if self.selected?.id == item.id { self.closeDetail() }
            await self.refresh()
        }
    }
    func prepareSpeech() { Task { await audio.prepareSpeechAssets(); notice = audio.issue ?? audio.speechStatus } }
    func requestAccessibility() { input.requestPermission() }
    func revealData() { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
    func loadMore() { pageLimit += 100; scheduleRefresh() }
    func previewCleanup() async -> Bool {
        guard !preparingCleanup else { return false }
        preparingCleanup = true
        defer { preparingCleanup = false }
        cleanupIDs = []; cleanupCount = 0
        do {
            let rows = try await store.cleanupCandidates(olderThan: Date.now.addingTimeInterval(-30 * 86400))
            cleanupIDs = rows.map(\.id); cleanupCount = rows.count
            if rows.isEmpty { notice = "没有可清理的原音。待识别、失败、收藏及使用中的原音会保留。" }
            return !rows.isEmpty
        } catch { notice = error.localizedDescription; return false }
    }
    func performCleanup() {
        let ids = cleanupIDs
        perform { let count = try await self.store.cleanupAudio(recordingIDs: ids, olderThan: Date.now.addingTimeInterval(-30 * 86400)); self.notice = "已清理 \(count) 条原音，文字和版本全部保留。"; self.lastStorageRefresh = .distantPast; await self.refresh() }
    }
    func prepareForExit() async {
        await audio.pause(); input.invalidate()
        editorDebounce?.cancel()
        _ = await flushEditorDrafts()
        // If saving fails, the delegate keeps this window open and the normal refresh loop alive.
        if !hasUnpersistedDrafts { timer?.cancel(); refreshTask?.cancel() }
    }
    // All callers await the same in-flight refresh, including startup diagnostics.
    // A timer refresh must not make a user action or initial render return empty early.
    func refresh() async {
        if let refreshOperation { await refreshOperation.value; return }
        let operation = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        refreshOperation = operation
        await operation.value
        refreshOperation = nil
    }
    func initialLoad() async { await refresh() }
    private func performRefresh() async {
        let requestedQuery = query, requestedFilter = recordFilter, requestedLimit = pageLimit
        do {
            await recoveryTask?.value
            var rows: [Recording] = []
            while rows.count < requestedLimit + 1 {
                let batch = try await store.listRecordings(query: requestedQuery, limit: min(100, requestedLimit + 1 - rows.count), offset: rows.count, filter: requestedFilter)
                rows += batch
                if batch.isEmpty { break }
            }
            guard query == requestedQuery, recordFilter == requestedFilter, pageLimit == requestedLimit else { scheduleRefresh(); return }
            hasMore = rows.count > requestedLimit
            records = Array(rows.prefix(requestedLimit)).map { DisplayRecording(source: $0) }
            let latest = try await store.listRecordings(query: "", limit: 30, offset: 0)
            var panelRows = latest.filter { $0.createdAt >= panelSessionStartedAt || stagedRecordIDs.contains($0.id) }
            for id in stagedRecordIDs where !panelRows.contains(where: { $0.id == id }) {
                if let row = try await store.recording(id: id) { panelRows.append(row) }
                else { stagedRecordIDs.remove(id) }
            }
            recent = panelRows.sorted { $0.createdAt < $1.createdAt }.map { DisplayRecording(source: $0) }
            if let selection = selected {
                let refreshedSelection = try await store.recording(id: selection.id).map { DisplayRecording(source: $0) }
                if selected?.id == selection.id {
                    selected = refreshedSelection
                    if editorRecordingID == selection.id, !editorWasEdited, let refreshedSelection { editorDraft = refreshedSelection.text }
                    if refreshedSelection?.source.preferredRevisionID != selection.source.preferredRevisionID { await loadVersions(selection.id) }
                }
            }
            if Date.now.timeIntervalSince(lastStorageRefresh) > 60 {
            lastStorageRefresh = Date.now
            let summary = try await store.storageSummary()
            storageLabel = ByteCountFormatter.string(fromByteCount: summary.audioBytes, countStyle: .file)
            if summary.shouldWarn { notice = "原音空间已达到提醒阈值，或磁盘剩余不足 1 GB。请在设置中查看存储。" }
            }
            if directMode {
                for record in latest.reversed() {
                    guard let revision = try await store.latestFinalRevision(recordingID: record.id), !directRevisions.contains(revision.id) else { continue }
                    directRevisions.insert(revision.id)
                    let result = await input.insertStable(recordingID: record.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count, recordingStartedAt: record.createdAt)
                    switch result { case .failed, .cancelled, .unverified: notice = result.message; default: break }
                }
            }
        } catch { notice = error.localizedDescription }
    }
    private func loadVersions(_ id: UUID) async {
        do {
            let loaded = try await store.revisions(recordingID: id).map {
                DisplayVersion(id: $0.id, text: $0.text, label: ($0.origin == .userEdit ? "手动修改" : "语音识别") + " · " + $0.createdAt.formatted(date: .omitted, time: .shortened))
            }
            guard selected?.id == id else { return }
            versions = loaded
        } catch { if selected?.id == id { notice = error.localizedDescription } }
    }
    private func scheduleRefresh() { refreshTask?.cancel(); refreshTask = Task { try? await Task.sleep(for: .milliseconds(200)); guard !Task.isCancelled else { return }; await refresh() } }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) { Task { do { try await operation() } catch { notice = error.localizedDescription } } }
    private func setLoginItem() {
        guard !initializing else { return }
        do { if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { notice = "登录启动未能更新：\(error.localizedDescription)" }
    }
}
