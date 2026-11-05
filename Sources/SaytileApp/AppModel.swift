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
    @Published var recordFilter: RecordingFilter = .all { didSet { pageLimit = 100; scheduleRefresh() } }
    @Published var query = "" { didSet { pageLimit = 100; scheduleRefresh() } }
    @Published var notice: String?
    @Published var directMode = false
    @Published var targetLabel = "在目标草稿中放置光标，再绑定"
    @Published var hasStarted = false
    @Published var storageLabel = "计算中…"
    @Published var cleanupCount = 0
    @Published var deviceID: UInt32 = 0 { didSet { audio.selectedDeviceID = deviceID } }
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
    private var refreshing = false
    private var initializing = true
    private var captureWasEnabled = false
    private var lastStorageRefresh = Date.distantPast
    private var recovered = false
    private var recoveryTask: Task<Void, Never>?

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
        Task {
            do {
                _ = try await input.bindCurrentTarget()
                for item in recent where !item.text.isEmpty {
                    guard let revision = item.source.preferredRevisionID else { continue }
                    let result = await input.insert(recordingID: item.id, revisionID: revision)
                    notice = result.message
                }
            } catch { notice = error.localizedDescription }
        }
    }
    func select(_ item: DisplayRecording) {
        selected = item; openArchive()
        Task { await loadVersions(item.id) }
    }
    func saveEdit(_ item: DisplayRecording, text: String) { perform { _ = try await self.store.saveEdit(recordingID: item.id, text: text); await self.refresh(); await self.loadVersions(item.id) } }
    func pin(_ item: DisplayRecording) { perform { try await self.store.setPinned(recordingID: item.id, pinned: !item.pinned); await self.refresh() } }
    func retry(_ item: DisplayRecording) { Task { await audio.retry(recordingID: item.id); await refresh() } }
    func play(_ item: DisplayRecording) {
        perform {
            if self.audio.playingID == item.id { self.audio.stopPlayback() }
            else { try await self.audio.play(recordingID: item.id) }
        }
    }
    func eraseAudio(_ item: DisplayRecording) { perform { try await self.store.deleteAudio(recordingID: item.id); await self.refresh() } }
    func deleteRecord(_ item: DisplayRecording) { perform { try await self.store.deleteRecord(recordingID: item.id); self.selected = nil; await self.refresh() } }
    func prepareSpeech() { Task { await audio.prepareSpeechAssets(); notice = audio.issue ?? audio.speechStatus } }
    func requestAccessibility() { input.requestPermission() }
    func revealData() { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
    func loadMore() { pageLimit += 100; scheduleRefresh() }
    func previewCleanup() {
        cleanupIDs = []; cleanupCount = 0
        perform {
            let rows = try await self.store.cleanupCandidates(olderThan: Date.now.addingTimeInterval(-30 * 86400))
            self.cleanupIDs = rows.map(\.id); self.cleanupCount = rows.count
        }
    }
    func performCleanup() {
        let ids = cleanupIDs
        perform { let count = try await self.store.cleanupAudio(recordingIDs: ids, olderThan: Date.now.addingTimeInterval(-30 * 86400)); self.notice = "已清理 \(count) 条原音，文字和版本全部保留。"; self.lastStorageRefresh = .distantPast; await self.refresh() }
    }
    func prepareForExit() async { await audio.pause(); input.invalidate() }
    func refresh() async {
        guard !refreshing else { return }; refreshing = true; defer { refreshing = false }
        do {
            await recoveryTask?.value
            var rows: [Recording] = []
            while rows.count < pageLimit + 1 {
                let batch = try await store.listRecordings(query: query, limit: min(100, pageLimit + 1 - rows.count), offset: rows.count, filter: recordFilter)
                rows += batch
                if batch.isEmpty { break }
            }
            hasMore = rows.count > pageLimit
            records = Array(rows.prefix(pageLimit)).map { DisplayRecording(source: $0) }
            let latest = try await store.listRecordings(query: "", limit: 30, offset: 0)
            recent = latest.reversed().map { DisplayRecording(source: $0) }
            if let selection = selected {
                selected = try await store.recording(id: selection.id).map { DisplayRecording(source: $0) }
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
            versions = try await store.revisions(recordingID: id).map {
                DisplayVersion(id: $0.id, text: $0.text, label: ($0.origin == .userEdit ? "手动修改" : "语音识别") + " · " + $0.createdAt.formatted(date: .omitted, time: .shortened))
            }
        } catch { notice = error.localizedDescription }
    }
    private func scheduleRefresh() { refreshTask?.cancel(); refreshTask = Task { try? await Task.sleep(for: .milliseconds(200)); guard !Task.isCancelled else { return }; await refresh() } }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) { Task { do { try await operation() } catch { notice = error.localizedDescription } } }
    private func setLoginItem() {
        guard !initializing else { return }
        do { if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { notice = "登录启动未能更新：\(error.localizedDescription)" }
    }
}
