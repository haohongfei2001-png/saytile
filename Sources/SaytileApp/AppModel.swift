import SaytileVoiceUI
import AppKit
import SwiftUI
import Combine
import ServiceManagement
import Network
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
        case .cancelled: return text.isEmpty ? "识别已停止" : "文字已保留"
        }
    }
    var emptyTextLabel: String {
        switch source.audioState {
        case .deleted: return "原音已删除，这条记录没有文字。"
        case .deletePending: return "正在清理原音，这条记录没有文字。"
        case .missing: return "原音暂不可用，尚未生成文字。"
        case .available:
            if source.isRecording { return "正在接收讲话…" }
            if !hasAudio { return "尚无转写文字或可回听的原音。" }
            if source.recognitionState == .failed { return "尚未转写，可回听或重新识别。" }
            if source.recognitionState == .completed { return "原音已保存，未检测到可识别的文字。" }
            return "原音已保存，等待识别…"
        }
    }
    var audioLabel: String {
        switch source.audioState {
        case .available: return source.duration > 0 ? "原音 · \(max(1, Int(source.duration.rounded()))) 秒" : (source.isRecording ? "原音保存中" : "尚无可回放原音")
        case .deleted: return source.duration == 0 ? "仅文字" : "原音已删除 · 文字保留"
        case .deletePending: return "原音清理中"
        case .missing: return "原音文件缺失"
        }
    }
}
struct ArchiveDisplayGroup: Identifiable, Equatable {
    let id: Int64
    let date: Date
    let day: String
    let utcOffset: Int
    var items: [DisplayRecording]

    static func from(_ entries: ArraySlice<TimelineEntry>) -> [Self] {
        var groups: [Self] = []
        // Read the visible slice in speaking order, then put the newest session first.
        for entry in entries.reversed() {
            let item = DisplayRecording(source: entry.recording)
            if groups.last?.id == entry.group {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(Self(id: entry.group, date: entry.groupStart, day: entry.groupDay,
                                   utcOffset: entry.groupUTCOffset, items: [item]))
            }
        }
        return groups.reversed()
    }
}

struct DisplayVersion: Identifiable {
    let id: UUID
    let text: String
    let label: String
}
struct DisplayDevice: Identifiable { let id: String?; let name: String }

/// Narrow injection for the actual settings controller. Fixtures never need the
/// production credential namespace or a second implementation of the UI workflow.
@MainActor
struct AppConnectionDependencies {
    var presence: (ModelConfiguration) -> CloudCredentialPresence
    var save: (String, ModelConfiguration) throws -> Void
    var delete: (ModelConfiguration) throws -> Void
    var verify: (RecognitionConfiguration, @escaping @Sendable (CloudConnectionReport) -> Void) async throws -> CloudConnectionReport
    var applyConfiguration: (AudioController, RecognitionConfiguration) async -> Void
    var revokeCloud: (AudioController) -> Void
    var applyNextRoute: (AudioController, RecognitionConfiguration) -> Void = { $0.setRouteForNextUtterance($1) }
    static let live = AppConnectionDependencies(
        presence: { CloudCredentialStore.presence(configurationID: $0.id, provider: $0.provider) },
        save: { try CloudCredentialStore.save($0, configurationID: $1.id, provider: $1.provider) },
        delete: { try CloudCredentialStore.delete(configurationID: $0.id, provider: $0.provider) },
        verify: { try await CloudConnectionVerifier.verify(configuration: $0, authorized: true, progress: $1) },
        applyConfiguration: { await $0.setRecognitionConfiguration($1) },
        revokeCloud: { $0.revokeCloudRecognition() })
}

/// The production actions remain AudioController's existing lifecycle. Native UI
/// checks inject only this boundary so pressing the real control never opens a mic.
@MainActor
struct AppCaptureDependencies {
    var state: (AudioController) -> CaptureState
    var start: (AudioController) async -> Void
    var pause: (AudioController) async -> Void
    var level: (AudioController) -> Float? = { $0.level }
    var microphoneAuthorization: () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) }
    var openMicrophonePreferences: () -> Void = {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
    }
    static let live = AppCaptureDependencies(state: { $0.state },
        start: { await $0.start() }, pause: { await $0.pause() })
}

/// Three ordinary states plus explicit preparation/failure exceptions. These values
/// describe one control; their labels are accessibility/settings text, not a header.
typealias PanelCaptureVisualState = VoicePanelState

struct PanelCapturePresentation: Equatable {
    let state: PanelCaptureVisualState
    let label: String
    let actionLabel: String
    let actionSymbolName: String
    let symbolName: String
    let detail: String?
    /// A measured level only while VAD reports speech. nil means no amplitude
    /// evidence, including an ASR/fusion wait; never drive a fabricated idle pulse.
    let liveVoiceLevel: Double?
    var accessibilityLabel: String { actionLabel }
    var accessibilityValue: String { detail.map { label + "，" + $0 } ?? label }

    init(state capture: CaptureState, hasStarted: Bool, measuredLevel: Float? = nil, microphoneDenied: Bool = false) {
        if case .speaking = capture, let measuredLevel, measuredLevel.isFinite, measuredLevel >= 0 {
            liveVoiceLevel = Double(min(1, measuredLevel))
        } else { liveVoiceLevel = nil }
        switch capture {
        case .paused:
            state = .paused
            label = "暂停"
            actionLabel = hasStarted ? "继续收音" : "开始收音"
            actionSymbolName = "play.fill"
            symbolName = "play.fill"
            detail = nil
        case .starting:
            state = .starting; label = "正在准备"; actionLabel = "取消开启"
            actionSymbolName = "xmark"; symbolName = "xmark"; detail = nil
        case .listening, .speaking:
            // Follow current voice activity, independently of earlier ASR/fusion
            // work. A finished utterance returns to standby while text settles.
            let active = capture == .speaking
            state = active ? .recognizing : .standby
            label = active ? "正在识别" : "待命"
            actionLabel = "暂停收音"; actionSymbolName = "pause.fill"
            symbolName = active ? "waveform" : "circle.fill"; detail = nil
        case .interrupted(let reason):
            state = .recoveryNeeded; label = "需要恢复"; actionLabel = microphoneDenied ? "打开麦克风权限设置" : "恢复收音"
            actionSymbolName = "play.fill"; symbolName = "exclamationmark"; detail = reason
        }
    }
}

/// Only an offline-to-online edge can retry a transient download. The edge may
/// arrive while URLSession is still completing the failed request.
struct ModelDownloadReconnect {
    private var available: Bool?
    private(set) var generation: UInt64 = 0
    private var waiting = false

    mutating func update(available next: Bool) -> Bool {
        defer { available = next }
        guard available == false && next else { return false }
        generation &+= 1
        defer { waiting = false }
        return waiting
    }

    mutating func interrupted(since start: UInt64) -> Bool {
        waiting = generation == start
        return !waiting
    }

    mutating func cancel() { waiting = false }
}

@MainActor
final class AppModel: ObservableObject {
    let store: SaytileStore
    let localModels: LocalASRService
    @Published private(set) var deviceOnly: Bool
    @Published private(set) var manualLocalModel: LocalASRID?
    @Published private(set) var archiveLocalModel: LocalASRID?
    @Published private(set) var localTextAllowed: Bool
    private var localReview: LocalTextReview?
    @Published private(set) var selectedLocalModel: LocalASRID = .apple
    @Published private(set) var localFallbackMessage: String?
    private let managesLocalModels: Bool
    private var unavailableLocalModels: Set<LocalASRID> = []
    private var selectionGeneration = 0
    private(set) var localEngineGeneration: UInt64 = 0
    private var attemptedAutomaticDownload = false
    private var automaticTransfer: Task<Void, Never>?
    private var downloadNetworkMonitor: NWPathMonitor?
    private var downloadReconnect = ModelDownloadReconnect()

    private var accountRoute: HostedRoute = .byok
    let audio: AudioController
    let input: NativeInputCoordinator
    let directory: URL
    let hosted: HostedAccount
    private let preferences: UserDefaults
    private let connectionDependencies: AppConnectionDependencies
    private let captureDependencies: AppCaptureDependencies
    let copyPasteboard: NSPasteboard?
    private var copyFeedback: Task<Void, Never>?
    // Sound level updates redraw the control, but do not invalidate transcript text.
    private(set) var timelineRenderRevision: UInt64 = 0
    @Published private(set) var timeline = TimelinePage() {
        didSet { timelineRenderRevision &+= 1 }
    }
    @Published private(set) var timelineTail: TimelineEntry?
    @Published private var latestTextEntry: TimelineEntry?
    @Published private(set) var timelineIdle = false
    @Published private(set) var timelineIdleSeconds: Int
    @Published private(set) var timelineFocus: Int64?
    private var timelineWindow = TimelineWindow.latest
    private var hiddenThrough: Int64 = 0 { didSet { timelineRenderRevision &+= 1 } }

    /// Only an explicit Clear starts an empty board. Opening an archived row
    /// still shows its surrounding history; a pause never changes this boundary.
    var panelTimelinePage: TimelinePage {
        guard hiddenThrough > 0, timelineFocus == nil else { return timeline }
        guard timeline.entries.first.map({ $0.position <= hiddenThrough }) == true else { return timeline }
        var page = timeline
        page.entries.removeAll { $0.position <= hiddenThrough }
        page.hasOlder = false
        return page
    }
    @Published var recent: [DisplayRecording] = []
    @Published private(set) var archiveGroups: [ArchiveDisplayGroup] = []
    var records: [DisplayRecording] { archiveGroups.flatMap(\.items) }
    private var archiveEditingID: UUID?
    private var archiveEditGeneration: UInt64 = 0
    @Published var versions: [DisplayVersion] = []
    @Published var archiveIsKey = false
    @Published var selected: DisplayRecording?
    @Published private(set) var editorDraft = ""
    @Published private(set) var editorDraftLoading = false
    @Published private(set) var savingEditorChanges = false
    @Published private(set) var editorConflictingVersion: Recording?
    @Published private(set) var editorDraftStatus = "修改会自动暂存，保存后更新这段文字"
    private var archiveIncludesUntranscribed = false
    @Published var recordFilter: RecordingFilter = .transcribed { didSet { archiveEditingID = nil; pageLimit = 100; scheduleRefresh() } }
    @Published var query = "" { didSet { archiveEditingID = nil; pageLimit = 100; scheduleRefresh() } }
    @Published var notice: String?
    private var captureStartIssue: (reason: String, detail: String)?
    @Published var recognitionConfiguration = RecognitionConfiguration() {
        didSet {
            guard !initializing, CloudConnectionVerifier.fingerprint(oldValue) != CloudConnectionVerifier.fingerprint(recognitionConfiguration) else { return }
            var rerouted = oldValue
            rerouted.manualASRConfigurationID = recognitionConfiguration.manualASRConfigurationID
            rerouted.languagePreference = recognitionConfiguration.languagePreference
            invalidateConnectionVerification(nextUtteranceOnly: rerouted == recognitionConfiguration)
        }
    }
    private var changingRoute = false
    @Published private(set) var connectionReport: CloudConnectionReport?
    @Published private(set) var checkingConnection = false
    @Published var connectionCheckAuthorized = false
    private var connectionCheckTask: Task<Void, Never>?
    private var connectionCheckID: UUID?
    private var recognitionApplyTask: Task<Void, Never>?
    private var recognitionApplyID = UUID()
    private static let connectionReceiptKey = "cloudConnectionReceipt.v1"
    var connectionVerified: Bool { connectionReport?.canEnableCloud == true && connectionReport?.matches(recognitionConfiguration) == true }
    @Published private(set) var appliedRecognitionConfiguration = RecognitionConfiguration()
    @Published private(set) var applyingRecognitionSettings = false
    var hasUnappliedRecognitionSettings: Bool { recognitionConfiguration != appliedRecognitionConfiguration }
    @Published var recognitionSettingsNotice: String?
    @Published var modelCallSummary: [String] = []
    @Published private(set) var lastASR: String?
    @Published var directMode = false
    @Published private(set) var insertionLabels: [UUID: String] = [:]
    @Published var targetLabel = "在目标草稿中放置光标，再绑定"
    @Published private(set) var completedFirstTranscript = false
    @Published var hasStarted = false
    @Published var storageLabel = "计算中…"
    @Published var cleanupCount = 0
    @Published private(set) var preparingCleanup = false
    @Published private(set) var isInserting = false
    var deviceUID: String? {
        get { audio.selectedDeviceUID }
        set {
            audio.selectDevice(uid: newValue)
            preferences.set(newValue, forKey: "selectedDeviceUID")
        }
    }
    @Published var shortcutChoice = "option-space" {
        didSet {
            guard !initializing else { return }
            preferences.set(shortcutChoice, forKey: "shortcutChoice")
            NotificationCenter.default.post(name: .init("SaytileShortcutChanged"), object: nil)
        }
    }
    @Published var panelBorderVisible = true {
        didSet {
            guard !initializing, panelBorderVisible != oldValue else { return }
            preferences.set(panelBorderVisible, forKey: "panelBorderVisible")
        }
    }
    @Published var floatingEntryEnabled = false {
        didSet {
            guard !initializing, floatingEntryEnabled != oldValue else { return }
            preferences.set(floatingEntryEnabled, forKey: "floatingEntryEnabled")
            NotificationCenter.default.post(name: .init("SaytileFloatingEntryChanged"), object: nil)
        }
    }
    let canManageLoginItem: Bool
    @Published private(set) var launchAtLogin = false
    @Published var hasMore = false
    @Published private(set) var panelCount = 0
    @Published private(set) var panelHasMore = false
    @Published private(set) var loadingPanel = false
    var openPanel: () -> Void = {}
    var hidePanel: () -> Void = {}
    var openArchive: () -> Void = {}
    var openSettings: () -> Void = {}
    var checkForUpdates: (() -> Void)?
    private var pageLimit = 100
    private var panelLimit = 100
    private var timer: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var recognitionSubscription: AnyCancellable?
    private var cleanupIDs: [UUID] = []
    private var refreshOperation: Task<Void, Never>?
    private var fullRefreshRequested = false
    private var refreshVersion: UInt64 = 0
    private var completedRefreshVersion: UInt64 = 0
    private var refreshOperationID = UUID()
    // Counts actual database refresh passes, not callers, for bounded-work diagnostics.
    private(set) var refreshReadPasses: UInt64 = 0
    private var initializing = true
    private var exitPrepared = false
    private var preparingForExit = false
    private var exitWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastStorageRefresh = Date.distantPast
    private var lastModelCallRefresh = Date.distantPast
    private var recovered = false
    private var recoveryTask: Task<Void, Never>?
    private var panelSessionStartedAt = Date()
    private var stagedRecordIDs: Set<UUID> = []
    private struct DraftWrite: Equatable {
        let sequence: UInt64
        let text: String
        let removesDraft: Bool
        var base: UUID?
    }
    private var editorBase: UUID?
    private var editorRecordingID: UUID?
    private var editorWasEdited = false
    private var editorSelectionGeneration = UUID()
    private var draftSequence: UInt64 = 0
    private var pendingDraftWrites: [UUID: DraftWrite] = [:]
    private var latestEditorValues: [UUID: DraftWrite] = [:]
    private var committingEditorIDs: Set<UUID> = []
    var editorCanEdit: Bool { editorRecordingID != nil && !editorDraftLoading }
    var hasUnpersistedDrafts: Bool { !pendingDraftWrites.isEmpty }

    init(directory: URL, preferences: UserDefaults = .standard, normalLaunch: Bool = false, connectionDependencies: AppConnectionDependencies = .live,
         captureDependencies: AppCaptureDependencies = .live, copyPasteboard: NSPasteboard? = nil) throws {
        managesLocalModels = normalLaunch
        canManageLoginItem = normalLaunch && SaytileStorageProfile.current == .standard
        localModels = LocalASRService(root: directory.appending(path: "LocalModels"))
        localTextAllowed = preferences.bool(forKey: "localASR.textAllowed")
        deviceOnly = preferences.object(forKey: "localASR.deviceOnly") as? Bool
            ?? (preferences.object(forKey: "hosted.selected.v1") == nil && preferences.data(forKey: "multiASRConfigurationV1") == nil)
        manualLocalModel = preferences.string(forKey: "localASR.manual").flatMap(LocalASRID.init(rawValue:)).flatMap { LocalASRID.consumer.contains($0) ? $0 : nil }
        archiveLocalModel = preferences.string(forKey: "localASR.archive").flatMap(LocalASRID.init(rawValue:)).flatMap { LocalASRID.consumer.contains($0) ? $0 : nil }
        self.directory = directory
        hosted = HostedAccount(preferences: preferences, production: normalLaunch && (Bundle.main.bundleIdentifier == "app.saytile.mac" || SaytileStorageProfile.current == .designExperience))
        self.preferences = preferences
        completedFirstTranscript = preferences.bool(forKey: "firstTranscript.v1")
        self.connectionDependencies = connectionDependencies
        self.captureDependencies = captureDependencies
        self.copyPasteboard = copyPasteboard
        store = try SaytileStore(directory: directory)
        timelineIdleSeconds = store.initialTimelineIdleSeconds
        var recognitionConfiguration = RecognitionConfiguration.load(from: preferences)
        let receipt = preferences.data(forKey: Self.connectionReceiptKey).flatMap { try? JSONDecoder().decode(CloudConnectionReport.self, from: $0) }
        connectionReport = receipt
        if recognitionConfiguration.cloudEnabled && !(receipt?.canEnableCloud == true && receipt?.matches(recognitionConfiguration) == true) {
            recognitionConfiguration.cloudEnabled = false
            try recognitionConfiguration.save(to: preferences)
            recognitionSettingsNotice = "云端连接尚未验证，暂用本机识别。可在设置中完成一次连接检查。"
        }
        recognitionConfiguration.checkedASRConfigurationID = receipt?.services.first(where: { $0.provider.isStreaming })?.id
        self.recognitionConfiguration = recognitionConfiguration
        self.appliedRecognitionConfiguration = recognitionConfiguration
        audio = AudioController(store: store, recognitionConfiguration: recognitionConfiguration, startupRecoveryReady: false)
        input = NativeInputCoordinator(store: store)
        panelBorderVisible = preferences.object(forKey: "panelBorderVisible") as? Bool ?? true
        floatingEntryEnabled = preferences.bool(forKey: "floatingEntryEnabled")
        launchAtLogin = canManageLoginItem && SMAppService.mainApp.status == .enabled
        shortcutChoice = preferences.string(forKey: "shortcutChoice") ?? ([.designExperience, .sharedVoicePreview, .mandarinCandidate].contains(SaytileStorageProfile.current) ? "disabled" : "option-space")
        audio.selectDevice(uid: preferences.string(forKey: "selectedDeviceUID"))
        initializing = false
        hosted.bind { [weak self] route, revoke in
            guard let self else { return }
            accountRoute = route
            audio.selectHostedRoute(deviceOnly ? .local : route, revoke: revoke)
            objectWillChange.send()
        }
        applyLocalSelection()
        if normalLaunch { Task { await refreshLocalRecommendation() } }
        input.onBindingInvalidated = { [weak self] in
            self?.directMode = false
            self?.targetLabel = "目标已改变，请重新绑定草稿"
            self?.notice = "自动输入已暂停，新内容继续保留在 Saytile。"
        }
        subscription = audio.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in guard let self else { return }
                self.objectWillChange.send()
                if case .interrupted = self.audio.state, self.input.binding != nil { self.input.invalidate() } }
        }
        recognitionSubscription = NotificationCenter.default.publisher(for: .init("SaytileRecognitionUpdated"))
            .throttle(for: .milliseconds(60), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in Task { @MainActor [weak self] in await self?.refreshRecognition() } }
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            do { _ = try await AudioDiagnostics.recoverAudio(store: store); recovered = true; audio.completeStartupRecovery() }
            catch { notice = "资料恢复尚未完成：\(error.localizedDescription)" }
        }
        startRefreshTimer()
    }
    private func startRefreshTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }
    var isListening: Bool {
        switch captureDependencies.state(audio) { case .listening, .speaking, .starting: return true; default: return false }
    }
    var panelCapturePresentation: PanelCapturePresentation {
        PanelCapturePresentation(state: captureDependencies.state(audio), hasStarted: hasStarted,
            measuredLevel: captureDependencies.level(audio), microphoneDenied: captureProblem && microphoneDenied)
    }
    var panelCaptureLabel: String { panelCapturePresentation.label }
    var panelCaptureDetail: String? {
        guard let reason = panelCapturePresentation.detail else { return nil }
        if let captureStartIssue, captureStartIssue.reason == reason, audio.issue == captureStartIssue.detail { return captureStartIssue.detail }
        return reason
    }
    var captureActionLabel: String { panelCapturePresentation.actionLabel }
    var captureActionSymbolName: String { panelCapturePresentation.actionSymbolName }
    var captureLabel: String { panelCaptureLabel }
    var captureProblem: Bool { if case .interrupted = captureDependencies.state(audio) { return true }; return false }
    var microphoneDenied: Bool { [.denied, .restricted].contains(captureDependencies.microphoneAuthorization()) }
    func openMicrophoneSettings() { captureDependencies.openMicrophonePreferences() }
    var microphoneLabel: String {
        switch captureDependencies.microphoneAuthorization() {
        case .authorized: return "已允许"
        case .notDetermined: return "开启收音时请求"
        default: return "未允许，请在系统设置中开启"
        }
    }
    var accessibilityLabel: String { input.hasPermission ? "已允许" : "尚未允许 · 可正常复制" }
    func recognitionPhaseLabel(for item: DisplayRecording) -> String {
        guard item.source.recognitionState == .running else { return item.stateLabel }
        return item.isRecording ? "正在记录" : "正在核对文字"
    }
    func selectSource(_ source: String, revoke: Bool = false) {
        if source != "local" && localTextAllowed { allowLocalText(false) }
        if source != "local" { cancelAutomaticDownload() }
        let changedLocalRoute = deviceOnly != (source == "local")
        if changedLocalRoute { localEngineGeneration &+= 1 }
        deviceOnly = source == "local"
        preferences.set(deviceOnly, forKey: "localASR.deviceOnly")
        hosted.select(source == "hosted")
        audio.selectHostedRoute(deviceOnly ? .local : accountRoute, revoke: revoke)
        if changedLocalRoute { applyLocalSelection() } else { audio.refreshLocalModelStatus() }
        if deviceOnly && managesLocalModels { Task { await refreshLocalRecommendation() } }
    }
    func allowHostedSpeech(_ enabled: Bool) {
        if enabled {
            selectSource("hosted")
            hosted.authorize(true)
        } else {
            hosted.authorize(false)
            if hosted.selected { selectSource("local") }
        }
    }
    var usesBYOK: Bool { !deviceOnly && !hosted.selected && appliedRecognitionConfiguration.cloudEnabled }
    func useBYOK(_ enabled: Bool) {
        if enabled {
            guard connectionVerified, !checkingConnection, !applyingRecognitionSettings else { return }
            recognitionConfiguration.cloudEnabled = true
            applyRecognitionSettings(selectingBYOK: true)
        } else if usesBYOK {
            selectSource("local", revoke: true)
            recognitionConfiguration.cloudEnabled = false
            var saved = appliedRecognitionConfiguration
            saved.cloudEnabled = false
            appliedRecognitionConfiguration = saved
            connectionDependencies.applyNextRoute(audio, saved)
            do { try saved.save(to: preferences) }
            catch { recognitionSettingsNotice = error.localizedDescription }
        }
    }
    func selectLocal(_ model: LocalASRID?, archiveOnly: Bool = false) {
        if archiveOnly {
            archiveLocalModel = model
            preferences.set(model?.rawValue, forKey: "localASR.archive")
        } else {
            guard model?.capability != .batch else { return }
            selectionGeneration += 1
            localEngineGeneration &+= 1
            if let model {
                cancelAutomaticDownload()
                unavailableLocalModels.remove(model)
                selectedLocalModel = model
            }
            localFallbackMessage = nil
            manualLocalModel = model
            preferences.set(model?.rawValue, forKey: "localASR.manual")
        }
        applyLocalSelection()
        if !archiveOnly && (managesLocalModels || model == nil) { Task { await refreshLocalRecommendation() } }
    }
    var localGPT: ModelConfiguration? {
        appliedRecognitionConfiguration.enabledModels.first { $0.purpose == .textFusion && $0.provider == .openAIResponses && $0.model == "gpt-6-astra" }
    }
    func allowLocalText(_ enabled: Bool) {
        localReview?.revoke(); localReview = nil
        localTextAllowed = enabled && deviceOnly && localGPT.map(hasCredential) == true
        preferences.set(localTextAllowed, forKey: "localASR.textAllowed")
        applyLocalSelection()
    }
    func refreshLocalRecommendation() async {
        selectionGeneration += 1
        let generation = selectionGeneration
        guard !exitPrepared, !preparingForExit else { return }
        let preferred = LocalModelRecommendation.preferred
        let requested = manualLocalModel
        let choices = [requested, preferred, .apple, .sherpa, .qwen].compactMap { $0 }
        var available: Set<LocalASRID> = []
        // Stop once the first usable engine is found. Never read unused weight files
        // solely to populate a routing decision.
        var checked: Set<LocalASRID> = []
        for id in choices where checked.insert(id).inserted && !unavailableLocalModels.contains(id) {
            if await localModels.availability(id).installed { available.insert(id) }
            guard generation == selectionGeneration, !exitPrepared, !preparingForExit else { return }
            if available.contains(id) { break }
        }
        let pick = LocalModelRecommendation.select(preferred: preferred, requested: requested,
                                                  available: available, unavailable: unavailableLocalModels)
        let firstChoice = requested ?? preferred
        if unavailableLocalModels.contains(firstChoice) || (requested != nil && !available.contains(firstChoice)) {
            localFallbackMessage = available.contains(pick)
                ? "\(firstChoice.title) 暂不可用，新讲话使用 \(pick.title)。"
                : "本地识别资源尚未就绪，原音会继续保存。"
        } else {
            localFallbackMessage = nil
        }
        if selectedLocalModel != pick {
            localEngineGeneration &+= 1
            selectedLocalModel = pick
            applyLocalSelection()
        }
        if managesLocalModels, deviceOnly, pick == .apple {
            audio.prepareLocalSpeechResourcesIfNeeded()
        }
        if managesLocalModels, deviceOnly, requested == nil, preferred != .apple,
           !available.contains(preferred), !unavailableLocalModels.contains(preferred), !attemptedAutomaticDownload,
           !preferences.bool(forKey: "localASR.pauseAutomatic." + preferred.rawValue) {
            let status = await localModels.library.status(preferred)
            guard selectionGeneration == generation, deviceOnly, !status.installed,
                  !preparingForExit, !exitPrepared, !attemptedAutomaticDownload,
                  !preferences.bool(forKey: "localASR.pauseAutomatic." + preferred.rawValue) else { return }
            attemptedAutomaticDownload = true
            monitorAutomaticDownloadNetwork()
            let startReconnection = downloadReconnect.generation
            guard let transfer = await localModels.library.download(preferred) else {
                // Another caller owns that transfer and its completion refresh.
                // In particular, do not cancel a manually requested download.
                return
            }
            automaticTransfer = transfer
            if !deviceOnly || manualLocalModel != nil || exitPrepared || preparingForExit
                || preferences.bool(forKey: "localASR.pauseAutomatic." + preferred.rawValue) {
                transfer.cancel()
            }
            await transfer.value
            let interrupted = await localModels.library.needsNetworkToResume(preferred)
            guard automaticTransfer == transfer else { return }
            automaticTransfer = nil
            if transfer.isCancelled { attemptedAutomaticDownload = false }
            if !transfer.isCancelled, interrupted {
                if downloadReconnect.interrupted(since: startReconnection) { attemptedAutomaticDownload = false }
            }
            await refreshLocalRecommendation()
        }
    }

    private func monitorAutomaticDownloadNetwork() {
        guard downloadNetworkMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in self?.downloadPathChanged(available: available) }
        }
        downloadNetworkMonitor = monitor
        monitor.start(queue: DispatchQueue(label: "app.saytile.model-connectivity"))
    }

    private func downloadPathChanged(available: Bool) {
        guard downloadReconnect.update(available: available) else { return }
        attemptedAutomaticDownload = false
        Task { await refreshLocalRecommendation() }
    }

    private func cancelAutomaticDownload() {
        automaticTransfer?.cancel()
        downloadReconnect.cancel()
        attemptedAutomaticDownload = false
    }

    func downloadLocalModel(_ id: LocalASRID) async {
        preferences.removeObject(forKey: "localASR.pauseAutomatic." + id.rawValue)
        await localModels.library.download(id)
        await localModels.library.waitForDownload(id)
        await refreshLocalRecommendation()
    }

    func pauseLocalModelDownload(_ id: LocalASRID) async {
        preferences.set(true, forKey: "localASR.pauseAutomatic." + id.rawValue)
        if id == LocalModelRecommendation.preferred { cancelAutomaticDownload() }
        await localModels.library.pause(id)
    }

    func removeLocalModel(_ id: LocalASRID) async throws {
        preferences.set(true, forKey: "localASR.pauseAutomatic." + id.rawValue)
        if id == LocalModelRecommendation.preferred { cancelAutomaticDownload() }
        try await localModels.delete(id)
        if archiveLocalModel == id { selectLocal(nil, archiveOnly: true) }
        if manualLocalModel == id { selectLocal(nil) }
        await refreshLocalRecommendation()
    }

    func isLocalChoiceFixed(_ id: LocalASRID) -> Bool {
        id == selectedLocalModel && id == manualLocalModel && !unavailableLocalModels.contains(id)
    }

    func localModelChoiceLabel(_ id: LocalASRID) -> String {
        if unavailableLocalModels.contains(id) { return "重试" }
        if id != selectedLocalModel { return "使用此模型" }
        return id == manualLocalModel ? "已选择" : "固定使用"
    }

    func localEngineUnavailable(_ id: LocalASRID, generation: UInt64) async {
        guard !exitPrepared, !preparingForExit, localEngineGeneration == generation,
              selectedLocalModel == id, unavailableLocalModels.insert(id).inserted else { return }
        await refreshLocalRecommendation()
    }

    func applyLocalSelection() {
        if deviceOnly, localTextAllowed, localReview == nil, let item = localGPT { localReview = LocalTextReview(model: item) }
        var onUnavailable: (@Sendable (LocalASRID) -> Void)?
        if managesLocalModels {
            let generation = localEngineGeneration
            onUnavailable = { [weak self] id in
                Task { @MainActor [weak self] in await self?.localEngineUnavailable(id, generation: generation) }
            }
        }
        let live = selectedLocalModel
        audio.selectLocalModels(live: live, archive: archiveLocalModel ?? live, service: localModels,
                                review: localReview, onUnavailable: onUnavailable)
    }
    var engineLabel: String { audio.speechStatus }
    func hasCredential(_ item: ModelConfiguration) -> Bool {
        credentialPresence(item).isSaved
    }
    func credentialPresence(_ item: ModelConfiguration) -> CloudCredentialPresence {
        connectionDependencies.presence(item)
    }
    @discardableResult func saveCredential(_ value: String, for item: ModelConfiguration) -> Bool {
        guard canChangeCredential(item) else { return false }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recognitionSettingsNotice = CloudCredentialError.empty.localizedDescription; return false
        }
        // Fence concurrent readers before the Keychain can expose a new account.
        // Even a failed mutation stays local until an explicit connection check.
        invalidateConnectionVerification()
        do {
            try connectionDependencies.save(value, item)
            rotateCredentialGeneration(for: item)
            recognitionSettingsNotice = "\(item.purpose.label)的密钥已安全保存。"
            return true
        } catch { recognitionSettingsNotice = error.localizedDescription; return false }
    }
    @discardableResult func removeCredential(for item: ModelConfiguration) -> Bool {
        guard canChangeCredential(item) else { return false }
        invalidateConnectionVerification()
        do {
            try connectionDependencies.delete(item)
            rotateCredentialGeneration(for: item)
            recognitionSettingsNotice = "该服务密钥已移除。"
            return true
        } catch { recognitionSettingsNotice = error.localizedDescription; return false }
    }
    private func canChangeCredential(_ item: ModelConfiguration) -> Bool {
        guard !preparingForExit, !exitPrepared else { return false }
        guard recognitionConfiguration.models.contains(where: { $0.id == item.id && $0.provider == item.provider }),
              appliedRecognitionConfiguration.models.contains(where: { $0.id == item.id }) else {
            recognitionSettingsNotice = "服务设置已更新，请重新打开该服务的密钥设置。"
            return false
        }
        return true
    }
    private func rotateCredentialGeneration(for item: ModelConfiguration) {
        let generation = UUID()
        // Persist via the applied local snapshot before the draft's observer can
        // save it. Otherwise restarting could restore the previous account scope.
        for index in appliedRecognitionConfiguration.models.indices where appliedRecognitionConfiguration.models[index].id == item.id {
            appliedRecognitionConfiguration.models[index].credentialGeneration = generation
        }
        let previousFingerprint = CloudConnectionVerifier.fingerprint(recognitionConfiguration)
        for index in recognitionConfiguration.models.indices where recognitionConfiguration.models[index].id == item.id {
            recognitionConfiguration.models[index].credentialGeneration = generation
        }
        // Disabled services are absent from the receipt fingerprint but still need
        // durable generations, and must supersede the pending pre-mutation apply.
        if previousFingerprint == CloudConnectionVerifier.fingerprint(recognitionConfiguration) {
            invalidateConnectionVerification()
        }
    }
    func applyRecognitionSettings() {
        applyRecognitionSettings(selectingBYOK: false)
    }
    private func applyRecognitionSettings(selectingBYOK: Bool) {
        guard !preparingForExit, !exitPrepared, !applyingRecognitionSettings, !checkingConnection else { return }
        var candidate = recognitionConfiguration
        candidate.checkedASRConfigurationID = connectionReport?.services.first(where: { $0.provider.isStreaming })?.id
        do {
            try candidate.validateForCloud()
            if candidate.cloudEnabled {
                guard connectionVerified else { throw ProviderFailure.configuration("请先完成连接检查，再启用云端识别。本机识别可以继续使用。") }
                for item in candidate.activeModels {
                    switch credentialPresence(item) {
                    case .saved: break
                    case .missing: throw ProviderFailure.configuration("请先保存\(item.purpose.label)的 API Key。")
                    case .unavailable(let status): throw CloudCredentialError.keychain(status)
                    }
                }
            }
            try candidate.save(to: preferences)
            recognitionConfiguration = candidate
            if (changingRoute || selectingBYOK) && candidate.cloudEnabled {
                connectionDependencies.applyNextRoute(audio, candidate)
                appliedRecognitionConfiguration = candidate
                if selectingBYOK { selectSource("byok") }
                changingRoute = false
                recognitionSettingsNotice = "已应用，新讲话使用所选模型。"
            } else {
                changingRoute = false
                scheduleRecognitionConfiguration(candidate, showNotice: true)
            }
        } catch { recognitionSettingsNotice = error.localizedDescription }
    }
    private func scheduleRecognitionConfiguration(_ candidate: RecognitionConfiguration, showNotice: Bool) {
        guard !preparingForExit, !exitPrepared else { return }
        recognitionApplyTask?.cancel()
        let previous = recognitionApplyTask
        let generation = UUID(); recognitionApplyID = generation; applyingRecognitionSettings = true
        recognitionApplyTask = Task {
            await previous?.value
            guard recognitionApplyID == generation, !Task.isCancelled else { return }
            await connectionDependencies.applyConfiguration(audio, candidate)
            guard recognitionApplyID == generation, !Task.isCancelled else { return }
            appliedRecognitionConfiguration = candidate; applyingRecognitionSettings = false
            if showNotice {
                recognitionSettingsNotice = candidate.cloudEnabled ? "识别设置已保存。" : "自带 API 的配置已保存。"
            }
        }
    }
    /// Credential or endpoint changes revoke the previous connection receipt immediately.
    private func invalidateConnectionVerification(nextUtteranceOnly: Bool = false) {
        changingRoute = nextUtteranceOnly
        connectionCheckID = nil; connectionCheckTask?.cancel()
        if localTextAllowed { allowLocalText(false) }
        connectionReport = nil; checkingConnection = false; connectionCheckAuthorized = false
        preferences.removeObject(forKey: Self.connectionReceiptKey)
        // Also revoke a not-yet-published in-flight cloud apply.
        var local = appliedRecognitionConfiguration; local.cloudEnabled = false
        if nextUtteranceOnly {
            recognitionApplyID = UUID()
            recognitionApplyTask?.cancel()
            applyingRecognitionSettings = false
            local.languagePreference = recognitionConfiguration.languagePreference
            local.manualASRConfigurationID = recognitionConfiguration.manualASRConfigurationID
            connectionDependencies.applyNextRoute(audio, local)
        } else { connectionDependencies.revokeCloud(audio) }
        appliedRecognitionConfiguration = local
        try? local.save(to: preferences)
        if !nextUtteranceOnly { scheduleRecognitionConfiguration(local, showNotice: false) }
        recognitionConfiguration.cloudEnabled = false
    }
    func cancelConnectionCheck() {
        connectionCheckID = nil; connectionCheckTask?.cancel()
        checkingConnection = false; connectionCheckAuthorized = false
        if var report = connectionReport {
            for index in report.services.indices where ![.verified, .failed, .cancelled].contains(report.services[index].state) {
                report.services[index].state = .cancelled
                report.services[index].code = "cancelled"
                report.services[index].message = "连接检查已停止。"
            }
            connectionReport = report
        }
        recognitionSettingsNotice = "连接检查已停止。本机识别可以继续使用；已发出的请求可能由服务商计费。"
    }
    func checkRecognitionConnections(activateOnSuccess: Bool = true) {
        guard !preparingForExit, !exitPrepared, connectionCheckAuthorized, !checkingConnection, !applyingRecognitionSettings else { return }
        let candidate = recognitionConfiguration
        let previous = connectionCheckTask
        invalidateConnectionVerification(nextUtteranceOnly: changingRoute)
        let generation = UUID(); connectionCheckID = generation; checkingConnection = true
        recognitionSettingsNotice = "正在用内置合成语音检查连接，不会打开麦克风。"
        connectionCheckTask = Task {
            // A cancelled older check must fully close its sockets before another starts.
            await previous?.value
            await recognitionApplyTask?.value
            guard connectionCheckID == generation, !Task.isCancelled else { return }
            do {
                let report = try await connectionDependencies.verify(candidate) { [weak self] report in
                    Task { @MainActor [weak self] in
                        guard let self, self.connectionCheckID == generation, self.checkingConnection else { return }
                        self.connectionReport = report
                    }
                }
                guard connectionCheckID == generation, !Task.isCancelled else { return }
                connectionReport = report; checkingConnection = false; connectionCheckAuthorized = false
                if report.canEnableCloud && report.matches(recognitionConfiguration) {
                    preferences.set(try JSONEncoder().encode(report), forKey: Self.connectionReceiptKey)
                    recognitionConfiguration.cloudEnabled = activateOnSuccess
                    applyRecognitionSettings()
                } else { recognitionSettingsNotice = report.message ?? "连接尚未完整通过，请查看各项服务状态。" }
            } catch {
                guard connectionCheckID == generation else { return }
                checkingConnection = false; connectionCheckAuthorized = false
                recognitionSettingsNotice = error is CancellationError ? "连接检查已停止。" : MultiConnectionMessage.safe(error)
            }
        }
    }
    var devices: [DisplayDevice] {
        var choices = [DisplayDevice(id: nil, name: "系统默认输入设备")] + audio.devices.map { DisplayDevice(id: $0.uid, name: $0.name) }
        if let uid = deviceUID, !choices.contains(where: { $0.id == uid }) {
            choices.append(DisplayDevice(id: uid, name: "已选择的麦克风未连接"))
        }
        return choices
    }
    var playingID: UUID? { audio.playingID }
    func toggleCapture() {
        if captureProblem && microphoneDenied { openMicrophoneSettings(); return }
        Task {
            await recoveryTask?.value
            guard recovered else { notice = "资料库恢复未完成，请先重新打开 Saytile。已有资料会保留。"; return }
            let prior = captureDependencies.state(audio)
            if prior.isRunning {
                if prior == .listening || prior == .speaking { hasStarted = true }
                await captureDependencies.pause(audio)
            } else {
                await captureDependencies.start(audio)
                let result = captureDependencies.state(audio)
                if result == .listening || result == .speaking { hasStarted = true }
            }
            if case let .interrupted(reason) = captureDependencies.state(audio), let issue = audio.issue {
                captureStartIssue = (reason, issue)
            } else { captureStartIssue = nil }
            objectWillChange.send()
        }
    }
    func setDirect(_ enabled: Bool) {
        directMode = enabled
        if !enabled { input.invalidate(); targetLabel = "在目标草稿中放置光标，再绑定" }
    }
    func bindTarget() {
        Task {
            do { let binding = try await input.bindCurrentTarget(); directMode = true; targetLabel = binding.label }
            catch { notice = error.localizedDescription }
        }
    }
    func moveTimeline(older: Bool) {
        guard !timeline.entries.isEmpty, older ? timeline.hasOlder : timeline.hasNewer else { return }
        let pivot = timeline.entries[timeline.entries.count / 2].position
        setTimelineWindow(older ? .ending(at: pivot) : .starting(at: pivot))
    }

    func pinTimeline() {
        if timelineWindow == .latest, let last = timeline.entries.last { setTimelineWindow(.ending(at: last.position)) }
    }

    func followTimeline() {
        timelineFocus = nil
        setTimelineWindow(.latest)
    }

    private var timelineRead: UInt64 = 0
    private var observedEnd: Date?
    private var observedPosition: Int64?
    private var silenceStarted = ContinuousClock.now
    private func refreshTimeline(_ window: TimelineWindow) async throws {
        // A delayed navigation task for a superseded window cannot invalidate a
        // newer read (including a refresh scheduled by the recognition stream).
        guard window == timelineWindow else { return }
        timelineRead &+= 1
        let request = timelineRead
        let (page, tail, textTail) = try await store.panelTimeline(window)
        guard window == timelineWindow, request == timelineRead else { return }
        if timeline != page { timeline = page }
        if !completedFirstTranscript, page.entries.contains(where: { !$0.recording.text.isEmpty }) || tail?.recording.text.isEmpty == false {
            completedFirstTranscript = true
            preferences.set(true, forKey: "firstTranscript.v1")
        }
        if timelineTail != tail { timelineTail = tail }
        if latestTextEntry != textTail { latestTextEntry = textTail }
        if observedPosition != tail?.position || observedEnd != tail?.speechEnd {
            observedPosition = tail?.position
            observedEnd = tail?.speechEnd
            let elapsed = min(3600, max(0, tail.map { Date.now.timeIntervalSince($0.speechEnd) } ?? 0))
            silenceStarted = .now - .seconds(elapsed)
        }
        let idle = tail.map { $0.position <= hiddenThrough || (!$0.recording.isRecording &&
            silenceStarted.duration(to: .now) >= .seconds(timelineIdleSeconds)) } ?? false
        if timelineIdle != idle { timelineIdle = idle }
    }

    private func setTimelineWindow(_ window: TimelineWindow) {
        guard window != timelineWindow else { return }
        timelineWindow = window
        Task {
            do { try await refreshTimeline(window) }
            catch { notice = error.localizedDescription }
        }
    }

    func changeIdleInterval(_ seconds: Int) {
        Task {
            do { try await store.setTimelineIdleSeconds(seconds); timelineIdleSeconds = seconds; await refresh() }
            catch { notice = error.localizedDescription }
        }
    }

    func editPanelRows(_ edits: [PanelRowEdit]) throws {
        guard !exitPrepared else { throw StoreError.database("资料库正在关闭。") }
        let createsRow = edits.contains { $0.before == nil }
        let window = createsRow ? .latest : timelineWindow
        let snapshot = try store.editTimeline(edits, window: window)
        timelineRead &+= 1 // Ignore a refresh which started before the edit.
        timelineWindow = window
        timeline = snapshot.page
        timelineTail = snapshot.tail
        latestTextEntry = snapshot.textTail
        if createsRow { timelineIdle = false }
        if !completedFirstTranscript {
            completedFirstTranscript = true
            preferences.set(true, forKey: "firstTranscript.v1")
        }
    }

    var canCopyLatestGroup: Bool { (latestTextEntry?.position ?? 0) > hiddenThrough }

    func copyTimeline(selection: String, displayed: [Int64: String]) {
        if !selection.isEmpty { copy(selection, quietly: true); return }
        guard let end = latestTextEntry, canCopyLatestGroup else { return }
        // The editor can hold a previous page across a new group. The click targets
        // the live tail while preserving the exact text of any already rendered rows.
        var snapshot = Dictionary(uniqueKeysWithValues: timeline.entries.map { ($0.position, $0.recording.text) })
        snapshot[end.position] = end.recording.text
        snapshot.merge(displayed) { _, rendered in rendered }
        do { copy(try store.timelineCopy(group: end.group, through: end.position, after: hiddenThrough, displayed: snapshot), quietly: true) }
        catch { notice = error.localizedDescription }
    }

    func copy(_ text: String, quietly: Bool = false) {
        guard !text.isEmpty else { return }
        copyFeedback?.cancel()
        if input.copy(text, to: copyPasteboard ?? .general) {
            if quietly { return }
            let success = "已复制，可以粘贴到任何应用。"
            notice = success
            copyFeedback = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                if self?.notice == success { self?.notice = nil }
            }
        } else {
            notice = "未能写入剪贴板，请再试一次。"
        }
    }
    var panelScopeLabel: String { panelHasMore ? "已载入 \(recent.count) / \(panelCount) 段" : "输入板 \(recent.count) 段" }
    func copyRecent() { copy(SaytileVoiceUI.VoiceTranscriptFlow.join(recent.map(\.text))) }
    func loadEarlierPanel() {
        guard !loadingPanel else { return }
        panelLimit += 100; refreshVersion &+= 1; loadingPanel = true
        Task { await refresh(); loadingPanel = false }
    }
    var insertionArchiveEntry: TimelineEntry? {
        guard let focus = timelineFocus else { return nil }
        return timeline.entries.first { $0.position == focus && stagedRecordIDs.contains($0.id) }
    }
    var hasPanelInsertionScope: Bool {
        if let archive = insertionArchiveEntry { return !archive.recording.text.isEmpty }
        return (timelineTail?.position ?? 0) > hiddenThrough
    }
    /// Resolve the exact group and immutable revisions at click time. An archive
    /// explicitly brought to the panel is a single-record reuse action.
    func panelInsertionSnapshots(rendered: [TimelineEntry] = [], displayed: [Int64: String] = [:]) throws -> [TimelineTextSnapshot] {
        let candidates: [TimelineTextSnapshot]
        if let entry = insertionArchiveEntry {
            candidates = [TimelineTextSnapshot(entry)]
        } else {
            guard let tail = timelineTail, tail.position > hiddenThrough else { return [] }
            candidates = try store.timelineGroupSnapshots(group: tail.group, through: tail.position)
                .filter { $0.position > hiddenThrough }
        }
        var seen = Dictionary(uniqueKeysWithValues: timeline.entries.map { ($0.position, TimelineTextSnapshot($0)) })
        if let tail = timelineTail { seen[tail.position] = TimelineTextSnapshot(tail) }
        for entry in rendered { seen[entry.position] = TimelineTextSnapshot(entry) }
        return candidates.compactMap { row in
            let snapshot = seen[row.position] ?? row
            guard snapshot.revisionID != nil, !snapshot.text.isEmpty, displayed[row.position] != "" else { return nil }
            return snapshot
        }
    }
    func insertFromPanel(rendered: [TimelineEntry], displayed: [Int64: String]) {
        guard !isInserting else { return }
        let snapshots: [TimelineTextSnapshot]
        do { snapshots = try panelInsertionSnapshots(rendered: rendered, displayed: displayed) }
        catch { notice = error.localizedDescription; return }
        guard !snapshots.isEmpty else { notice = "这段还没有可插入的文字。"; return }
        isInserting = true
        Task {
            defer { isInserting = false }
            do {
                let binding = try await input.bindCurrentTarget(purpose: .manual)
                var frozen: [TranscriptRevision] = []
                for snapshot in snapshots {
                    guard let revisionID = snapshot.revisionID else { return }
                    frozen.append(try await store.freezeRevision(recordingID: snapshot.recordingID, revisionID: revisionID, text: snapshot.text))
                }
                for snapshot in frozen {
                    guard input.binding?.id == binding.id else { notice = NativeInputResult.cancelled.message; return }
                    let result = await input.insert(recordingID: snapshot.recordingID, revisionID: snapshot.id)
                    notice = result.message
                    recordInputResult(result, recordingID: snapshot.recordingID)
                    // A batch is a single user action. Do not continue sending following records
                    // after an uncertain/failed attempt; a new action can explicitly reuse them.
                    guard result == .confirmed else { return }
                }
            } catch { notice = error.localizedDescription }
        }
    }
    private func recordInputResult(_ result: NativeInputResult, recordingID: UUID) {
        switch result {
        case .confirmed: insertionLabels[recordingID] = "已插入目标草稿"
        case .unverified: insertionLabels[recordingID] = "插入未确认 · 不会自动重发"
        case .correctionPending: insertionLabels[recordingID] = "修正版待处理 · 未自动重试"
        case .deferred: insertionLabels[recordingID] = "较早段的迟到文字 · 保留在此处供取用"
        case .cancelled: insertionLabels[recordingID] = "目标已变化 · 文字留在此处"
        case .failed: insertionLabels[recordingID] = "未能插入 · 可复制取用"
        case .noNewText: break
        }
    }
    func clearPanel() {
        guard !isInserting else { return }
        timelineFocus = nil
        setTimelineWindow(.latest)
        panelSessionStartedAt = Date()
        stagedRecordIDs.removeAll()
        panelLimit = 100; panelCount = 0; panelHasMore = false
        hiddenThrough = timelineTail?.position ?? 0
        timelineIdle = true
        recent = []
        notice = "输入板已清空，全部记录仍在语音档案中。"
    }
    func stageInPanel(_ item: DisplayRecording, showPanel: Bool = true) {
        stagedRecordIDs.insert(item.id)
        if !recent.contains(where: { $0.id == item.id }) { recent.append(item); recent.sort { $0.date < $1.date } }
        scheduleRefresh()
        if showPanel {
            openPanel()
            Task {
                if let position = try? await store.timelinePosition(of: item.id) {
                    timelineFocus = position
                    setTimelineWindow(.starting(at: position))
                }
            }
        }
        notice = "已在输入板定位这段文字。"
    }
    func select(_ item: DisplayRecording) {
        Task { await selectForEditing(item); openArchive() }
    }
    func prepareEditorIfNeeded(_ item: DisplayRecording) async {
        guard editorRecordingID != item.id, !(editorDraftLoading && selected?.id == item.id) else { return }
        await selectForEditing(item)
    }
    func selectForEditing(_ item: DisplayRecording) async {
        if editorRecordingID == item.id { selected = item; await loadVersions(item.id); return }
        let generation = UUID(); editorSelectionGeneration = generation
        selected = item; versions = []; editorDraftLoading = true; editorRecordingID = nil; editorDraft = ""; editorConflictingVersion = nil
        _ = await flushEditorDrafts()
        do {
            let stored = try await store.archiveDraft(recordingID: item.id)
            guard let current = try await store.recording(id: item.id) else { return }
            guard editorSelectionGeneration == generation, selected?.id == item.id else { return }
            let pending = pendingDraftWrites[item.id]
            let draft = pending?.text ?? stored?.text
            if let pending { editorBase = pending.base }
            else if let stored { editorBase = stored.base }
            else { editorBase = current.preferredRevisionID }
            selected = DisplayRecording(source: current)
            editorDraft = draft ?? current.text
            editorWasEdited = draft != nil
            editorRecordingID = item.id; editorDraftLoading = false
            editorDraftStatus = pendingDraftWrites[item.id] == nil ? "修改会自动暂存，保存后更新这段文字" : "草稿尚未写入磁盘，请保留此窗口"
            // Older builds could leave a durable draft after an edit was fully undone.
            if draft?.utf16.elementsEqual(current.text.utf16) == true, current.preferredRevisionID != nil {
                updateEditorDraft(current.text)
            }
            await loadVersions(item.id)
        } catch {
            if editorSelectionGeneration == generation { editorDraftStatus = "草稿读取失败，请重新选择记录"; notice = error.localizedDescription; editorDraftLoading = false }
        }
    }
    func closeDetail() {
        editorSelectionGeneration = UUID(); selected = nil; editorRecordingID = nil; editorConflictingVersion = nil
        Task { _ = await flushEditorDrafts() }
    }
    func updateEditorDraft(_ text: String) {
        guard let id = editorRecordingID, selected?.id == id, !editorDraftLoading else { return }
        // If a version is being saved, even returning to the old spelling is a newer edit.
        let removesDraft = !committingEditorIDs.contains(id) && selected?.source.preferredRevisionID != nil
            && selected?.text.utf16.elementsEqual(text.utf16) == true
        editorDraft = text
        editorWasEdited = !removesDraft
        draftSequence &+= 1
        if removesDraft { editorBase = selected?.source.preferredRevisionID; editorConflictingVersion = nil }
        let write = DraftWrite(sequence: draftSequence, text: text, removesDraft: removesDraft, base: editorBase)
        pendingDraftWrites[id] = write; latestEditorValues[id] = write
        _ = persistDraft(id, write: write)
    }

    private func persistDraft(_ id: UUID, write: DraftWrite) -> Bool {
        do {
            try store.writeArchiveDraft(recordingID: id, text: write.removesDraft ? nil : write.text, basedOn: write.base)
            pendingDraftWrites.removeValue(forKey: id)
            if editorRecordingID != id, !committingEditorIDs.contains(id) { latestEditorValues.removeValue(forKey: id) }
            if editorRecordingID == id {
                editorDraftStatus = write.removesDraft ? "修改会自动暂存，保存后更新这段文字" : "草稿已自动保留，保存修改创建版本"
            }
            return true
        } catch StoreError.missingRecording {
            pendingDraftWrites.removeValue(forKey: id); latestEditorValues.removeValue(forKey: id)
            return true
        } catch {
            editorDraftStatus = "草稿尚未写入磁盘，请勿退出"
            notice = "草稿保存失败：\(error.localizedDescription)"
            return false
        }
    }
    @discardableResult func flushEditorDrafts() async -> Bool {
        for (id, write) in pendingDraftWrites {
            if !persistDraft(id, write: write) { return false }
        }
        return true
    }
    func saveEditorChanges(reviewedRevision: UUID? = nil) async {
        guard let item = selected, editorRecordingID == item.id, !editorDraftLoading, !savingEditorChanges else { return }
        if let conflict = editorConflictingVersion {
            guard conflict.preferredRevisionID == reviewedRevision else { return }
        }
        let text = editorDraft, sequence = latestEditorValues[item.id]?.sequence
        savingEditorChanges = true; committingEditorIDs.insert(item.id)
        do {
            let revision = try await store.saveEdit(recordingID: item.id, text: text, clearingDraftMatching: text,
                                                    basedOn: reviewedRevision ?? editorBase)
            if editorRecordingID == item.id {
                editorBase = revision.id
                editorConflictingVersion = nil
            }
            if latestEditorValues[item.id]?.sequence == sequence {
                pendingDraftWrites.removeValue(forKey: item.id)
                if editorRecordingID == item.id { editorWasEdited = false; editorDraftStatus = "修改已保存" }
            } else if var newer = latestEditorValues[item.id] {
                // The just-committed version is the base of typing that arrived during save.
                newer.base = revision.id
                pendingDraftWrites[item.id] = newer
                latestEditorValues[item.id] = newer
            }
        } catch StoreError.archiveEditingConflict(let current) {
            if editorRecordingID == item.id {
                editorConflictingVersion = current
                editorDraftStatus = "另一处修改了这段文字。核对下方当前版本后，可将草稿存为新版本。"
            }
        } catch { notice = error.localizedDescription }
        committingEditorIDs.remove(item.id); savingEditorChanges = false
        _ = await flushEditorDrafts()
        await refresh(); await loadVersions(item.id)
    }
    func includeUntranscribed(_ include: Bool) {
        archiveIncludesUntranscribed = include
        recordFilter = include ? .all : .transcribed
        if !include, query.isEmpty, let selected, selected.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { closeDetail() }
    }
    func toggleFavoriteFilter() {
        if recordFilter == .pinned {
            includeUntranscribed(archiveIncludesUntranscribed)
        } else {
            archiveIncludesUntranscribed = recordFilter == .all
            recordFilter = .pinned
            if let selected, !selected.pinned { closeDetail() }
        }
    }
    func toggleFavorite(_ id: UUID) async {
        do {
            let nowPinned = try await store.togglePinned(recordingID: id)
            if !nowPinned, recordFilter == .pinned, selected?.id == id { closeDetail() }
            await refresh()
        } catch { notice = error.localizedDescription }
    }
    func retry(_ item: DisplayRecording) {
        let shownConfiguration = appliedRecognitionConfiguration
        Task { await audio.retry(recordingID: item.id, expectedConfiguration: shownConfiguration); await refresh() }
    }
    func play(_ item: DisplayRecording) {
        perform {
            if self.audio.playingID == item.id { self.audio.stopPlayback() }
            else { try await self.audio.play(recordingID: item.id) }
        }
    }
    func eraseAudio(_ item: DisplayRecording) {
        perform {
            try await self.store.deleteAudio(recordingID: item.id)
            await self.audio.cancelRecognition(recordingID: item.id)
            await self.refresh()
        }
    }
    func deleteRecord(_ item: DisplayRecording) {
        perform {
            try await self.store.deleteRecord(recordingID: item.id)
            await self.audio.cancelRecognition(recordingID: item.id)
            self.pendingDraftWrites.removeValue(forKey: item.id); self.latestEditorValues.removeValue(forKey: item.id)
            if self.selected?.id == item.id { self.closeDetail() }
            await self.refresh()
        }
    }
    func prepareSpeech() {
        Task {
            await audio.prepareSpeechAssets()
            if await AppleSpeechService.availability().installed {
                unavailableLocalModels.remove(.apple)
                await refreshLocalRecommendation()
            }
        }
    }
    func requestAccessibility() { input.requestPermission() }
    func revealData() { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
    func setArchiveEditing(_ id: UUID?) {
        guard archiveEditingID != id else { return }
        archiveEditingID = id
        if id == nil { scheduleRefresh() }
    }

    func endArchiveEditing(_ id: UUID) {
        guard archiveEditingID == id else { return }
        setArchiveEditing(nil)
    }

    func editArchiveText(_ id: UUID, before: String, after: String) throws {
        guard !exitPrepared else { throw StoreError.database("资料库正在关闭。") }
        let updated = try store.editArchiveParagraph(id: id, before: before, after: after)
        archiveEditGeneration &+= 1
        if let group = archiveGroups.firstIndex(where: { $0.items.contains { $0.id == id } }),
           let item = archiveGroups[group].items.firstIndex(where: { $0.id == id }) {
            archiveGroups[group].items[item] = DisplayRecording(source: updated)
        }
        scheduleRefresh()
    }

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
        perform { let count = try await self.store.cleanupAudio(recordingIDs: ids, olderThan: Date.now.addingTimeInterval(-30 * 86400)); self.notice = "已清理 \(count) 条原音，已保存的文字全部保留。"; self.lastStorageRefresh = .distantPast; await self.refresh() }
    }
    func prepareForExit() async {
        guard !exitPrepared else { return }
        if preparingForExit { await withCheckedContinuation { exitWaiters.append($0) }; return }
        preparingForExit = true
        defer {
            preparingForExit = false
            let waiters = exitWaiters; exitWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        directMode = false; input.invalidate()
        cancelConnectionCheck()
        recognitionApplyID = UUID(); recognitionApplyTask?.cancel(); connectionDependencies.revokeCloud(audio)
        await connectionCheckTask?.value; connectionCheckTask = nil
        await recognitionApplyTask?.value; recognitionApplyTask = nil; applyingRecognitionSettings = false
        timer?.cancel(); refreshTask?.cancel()
        await audio.pause()
        _ = await flushEditorDrafts()
        // If saving fails, the delegate keeps this window open and the normal refresh loop alive.
        if !hasUnpersistedDrafts {
            exitPrepared = true
            cancelAutomaticDownload()
            downloadNetworkMonitor?.cancel()
            downloadNetworkMonitor = nil
            timer?.cancel(); refreshTask?.cancel()
            await audio.shutdown()
            await refreshOperation?.value
            do { try await store.close() } catch { notice = error.localizedDescription }
        } else { startRefreshTimer() }
    }
    // All callers await the same in-flight refresh, including startup diagnostics.
    // A timer refresh must not make a user action or initial render return empty early.
    func refreshRecognition() async {
        // The board needs the newest text immediately. Archive and direct-input
        // consumers retain the full pass when active and on the regular timer.
        await refresh(transcriptOnly: !archiveIsKey && input.binding == nil)
    }

    func refresh(transcriptOnly: Bool = false) async {
        guard !exitPrepared else { return }
        if !transcriptOnly { fullRefreshRequested = true }
        refreshVersion &+= 1
        let requestedVersion = refreshVersion
        while !exitPrepared, completedRefreshVersion < requestedVersion {
            let operation: Task<Void, Never>
            let operationID: UUID
            if let pending = refreshOperation {
                operation = pending; operationID = refreshOperationID
            } else {
                operationID = UUID(); refreshOperationID = operationID
                // One pass covers all requests that arrived before it started.
                // A waiting caller retains its original version; recursively calling
                // refresh here would invent another request and serialize the burst.
                let coveredVersion = refreshVersion
                let full = fullRefreshRequested
                fullRefreshRequested = false
                operation = Task<Void, Never> { [weak self] in
                    guard let self else { return }
                    if full {
                        await self.performRefresh()
                    } else {
                        do { try await self.refreshTimeline(self.timelineWindow) }
                        catch { self.notice = error.localizedDescription }
                    }
                    self.completedRefreshVersion = max(self.completedRefreshVersion, coveredVersion)
                }
                refreshOperation = operation
            }
            await operation.value
            if refreshOperationID == operationID { self.refreshOperation = nil }
        }
    }
    func initialLoad() async { await refresh() }
    private func performRefresh() async {
        refreshReadPasses &+= 1
        let requestedQuery = query, requestedFilter = recordFilter, requestedLimit = pageLimit
        do {
            await recoveryTask?.value
            try await refreshTimeline(timelineWindow)
            let generation = archiveEditGeneration, editingID = archiveEditingID
            let entries = try await store.archiveEntries(query: requestedQuery, filter: requestedFilter,
                                                         limit: requestedLimit + 1, editingID: editingID)
            var visibleEntries = entries.prefix(requestedLimit)
            if let editingID, !visibleEntries.contains(where: { $0.id == editingID }),
               let focused = try await store.archiveEntryForEditing(editingID, filter: requestedFilter) {
                visibleEntries.append(focused)
            }
            guard query == requestedQuery, recordFilter == requestedFilter, pageLimit == requestedLimit,
                  archiveEditGeneration == generation, archiveEditingID == editingID else { scheduleRefresh(); return }
            let more = entries.count > requestedLimit
            if hasMore != more { hasMore = more }
            let groups = ArchiveDisplayGroup.from(visibleEntries)
            if archiveGroups != groups { archiveGroups = groups }
            let panelStart = panelSessionStartedAt, panelIDs = Array(stagedRecordIDs), requestedPanelLimit = panelLimit
            var panelRows: [Recording] = []
            while panelRows.count < requestedPanelLimit {
                let batch = try await store.listPanelRecordings(createdSince: panelStart, includingIDs: panelIDs, limit: min(100, requestedPanelLimit - panelRows.count), offset: panelRows.count)
                panelRows += batch
                if batch.isEmpty { break }
            }
            let total = try await store.panelRecordingCount(createdSince: panelStart, includingIDs: panelIDs)
            if panelStart == panelSessionStartedAt, Set(panelIDs) == stagedRecordIDs, requestedPanelLimit == panelLimit {
                if panelCount != total { panelCount = total }
                let morePanel = panelRows.count < total
                if panelHasMore != morePanel { panelHasMore = morePanel }
                let nextRecent = panelRows.reversed().map { DisplayRecording(source: $0) }
                if recent != nextRecent { recent = nextRecent }
            }
            if let selection = selected {
                let refreshedSelection = try await store.recording(id: selection.id).map { DisplayRecording(source: $0) }
                if selected?.id == selection.id {
                    if selected != refreshedSelection { selected = refreshedSelection }
                    if editorRecordingID == selection.id, !editorWasEdited, let refreshedSelection {
                        editorBase = refreshedSelection.source.preferredRevisionID
                        if editorDraft != refreshedSelection.text { editorDraft = refreshedSelection.text }
                    }
                    if refreshedSelection?.source.preferredRevisionID != selection.source.preferredRevisionID { await loadVersions(selection.id) }
                }
            }
            if Date.now.timeIntervalSince(lastModelCallRefresh) > 2 {
                lastModelCallRefresh = Date.now
                let summary = try await store.modelCallSummaries(limit: 30)
                if modelCallSummary != summary { modelCallSummary = summary }
                let actual = try await store.lastASREngine()
                if lastASR != actual { lastASR = actual }
            }
            if Date.now.timeIntervalSince(lastStorageRefresh) > 60 {
                lastStorageRefresh = Date.now
                let summary = try await store.storageSummary()
                let label = ByteCountFormatter.string(fromByteCount: summary.audioBytes, countStyle: .file)
                if storageLabel != label { storageLabel = label }
                let warning = "原音空间已达到提醒阈值，或磁盘剩余不足 1 GB。请在设置中查看存储。"
                if summary.shouldWarn, notice != warning { notice = warning }
            }
            let visibleIDs = Set(records.map(\.id) + recent.map(\.id))
            if !insertionLabels.keys.allSatisfy(visibleIDs.contains) {
                insertionLabels = insertionLabels.filter { visibleIDs.contains($0.key) }
            }
            if directMode && !isInserting, let binding = input.binding {
                for correction in try await store.ownedCorrectionCandidates(bindingID: binding.id) {
                    guard directMode, !isInserting, input.binding?.id == binding.id else { break }
                    recordInputResult(await input.repairOwned(revision: correction), recordingID: correction.recordingID)
                }
                let deferred = try await store.deferredDirectInputRecordings(bindingID: binding.id, createdSince: binding.boundAt, limit: 1000)
                for id in deferred where visibleIDs.contains(id) { recordInputResult(.deferred, recordingID: id) }
                let candidates = try await store.directInputCandidates(bindingID: binding.id, createdSince: binding.boundAt)
                for record in candidates {
                    guard directMode, !isInserting, input.binding?.id == binding.id else { break }
                    guard let revision = try await store.latestDispatchableRevision(recordingID: record.id) else { continue }
                    let result = await input.insertStable(recordingID: record.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count, recordingStartedAt: record.createdAt)
                    recordInputResult(result, recordingID: record.id)
                    switch result { case .failed, .cancelled, .unverified, .deferred: notice = result.message; default: break }
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
    private func scheduleRefresh() { refreshVersion &+= 1; refreshTask?.cancel(); refreshTask = Task { try? await Task.sleep(for: .milliseconds(200)); guard !Task.isCancelled else { return }; await refresh() } }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) { Task { do { try await operation() } catch { notice = error.localizedDescription } } }
    func setLoginItem(_ enabled: Bool) {
        guard canManageLoginItem else { return }
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { notice = "登录启动未能更新：\(error.localizedDescription)" }
        let status = SMAppService.mainApp.status
        if status == .requiresApproval { notice = "登录启动需要在系统设置的登录项中允许。收音仍需你主动开启。" }
        launchAtLogin = status == .enabled
    }
}

private enum MultiConnectionMessage {
    static func safe(_ error: Error) -> String {
        if let known = error as? ProviderFailure { return known.localizedDescription }
        if let known = error as? CloudCredentialError { return known.localizedDescription }
        return "连接检查未完成，请稍后重试。本机识别可以继续使用。"
    }
}
