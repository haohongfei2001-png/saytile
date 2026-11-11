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
            if source.recognitionState == .failed { return "原音已保存，文字等待恢复。" }
            if source.recognitionState == .completed { return "原音已保存，未检测到可识别的文字。" }
            return "原音已保存，等待识别…"
        }
    }
    var audioLabel: String {
        switch source.audioState {
        case .available: return source.duration > 0 ? "原音 · \(max(1, Int(source.duration.rounded()))) 秒" : (source.isRecording ? "原音保存中" : "尚无可回放原音")
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
    static let live = AppCaptureDependencies(state: { $0.state },
        start: { await $0.start() }, pause: { await $0.pause() })
}

/// Three ordinary states plus explicit preparation/failure exceptions. These values
/// describe one control; their labels are accessibility/settings text, not a header.
enum PanelCaptureVisualState: Equatable {
    case standby, recognizing, paused, starting, recoveryNeeded
}

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

    init(state capture: CaptureState, hasStarted: Bool, measuredLevel: Float? = nil) {
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
            state = .recoveryNeeded; label = "需要恢复"; actionLabel = "恢复收音"
            actionSymbolName = "play.fill"; symbolName = "exclamationmark"; detail = reason
        }
    }
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
    private var automaticLocal: LocalASRID = .apple
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
    @Published private(set) var timeline = TimelinePage()
    @Published private(set) var timelineTail: TimelineEntry?
    @Published private(set) var timelineIdle = false
    @Published private(set) var timelineIdleSeconds: Int
    @Published private(set) var timelineFocus: Int64?
    private var timelineWindow = TimelineWindow.latest
    private var hiddenThrough: Int64 = 0
    @Published var recent: [DisplayRecording] = []
    @Published var records: [DisplayRecording] = []
    @Published var versions: [DisplayVersion] = []
    @Published var archiveIsKey = false
    @Published var selected: DisplayRecording?
    @Published private(set) var editorDraft = ""
    @Published private(set) var editorDraftLoading = false
    @Published private(set) var savingEditorChanges = false
    @Published private(set) var editorDraftStatus = "修改会自动暂存，保存后更新这段文字"
    @Published var recordFilter: RecordingFilter = .all { didSet { pageLimit = 100; scheduleRefresh() } }
    @Published var query = "" { didSet { pageLimit = 100; scheduleRefresh() } }
    @Published var notice: String?
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
    @Published var directMode = false
    @Published private(set) var insertionLabels: [UUID: String] = [:]
    @Published var targetLabel = "在目标草稿中放置光标，再绑定"
    @Published var hasStarted = false
    @Published var storageLabel = "计算中…"
    @Published var cleanupCount = 0
    @Published private(set) var preparingCleanup = false
    @Published private(set) var isInserting = false
    @Published var deviceID: UInt32 = 0 {
        didSet {
            guard !initializing, deviceID != UInt32.max else { return }
            audio.selectedDeviceID = deviceID
            preferences.set(audio.selectedDeviceUID, forKey: "selectedDeviceUID")
        }
    }
    @Published var shortcutChoice = "option-space" {
        didSet {
            guard !initializing else { return }
            preferences.set(shortcutChoice, forKey: "shortcutChoice")
            NotificationCenter.default.post(name: .init("SaytileShortcutChanged"), object: nil)
        }
    }
    @Published var floatingEntryEnabled = false {
        didSet {
            guard !initializing, floatingEntryEnabled != oldValue else { return }
            preferences.set(floatingEntryEnabled, forKey: "floatingEntryEnabled")
            NotificationCenter.default.post(name: .init("SaytileFloatingEntryChanged"), object: nil)
        }
    }
    @Published var launchAtLogin = false { didSet { setLoginItem() } }
    @Published var hasMore = false
    @Published private(set) var panelCount = 0
    @Published private(set) var panelHasMore = false
    @Published private(set) var loadingPanel = false
    var openPanel: () -> Void = {}
    var hidePanel: () -> Void = {}
    var openArchive: () -> Void = {}
    var openSettings: () -> Void = {}
    private var pageLimit = 100
    private var panelLimit = 100
    private var timer: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var recognitionSubscription: AnyCancellable?
    private var cleanupIDs: [UUID] = []
    private var refreshOperation: Task<Void, Never>?
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

    init(directory: URL, preferences: UserDefaults = .standard, connectionDependencies: AppConnectionDependencies = .live,
         captureDependencies: AppCaptureDependencies = .live, copyPasteboard: NSPasteboard? = nil) throws {
        localModels = LocalASRService(root: directory.appending(path: "LocalModels"))
        localTextAllowed = preferences.bool(forKey: "localASR.textAllowed")
        deviceOnly = preferences.object(forKey: "localASR.deviceOnly") as? Bool
            ?? (preferences.object(forKey: "hosted.selected.v1") == nil && preferences.data(forKey: "multiASRConfigurationV1") == nil)
        manualLocalModel = preferences.string(forKey: "localASR.manual").flatMap(LocalASRID.init(rawValue:)).flatMap { LocalASRID.consumer.contains($0) ? $0 : nil }
        archiveLocalModel = preferences.string(forKey: "localASR.archive").flatMap(LocalASRID.init(rawValue:)).flatMap { LocalASRID.consumer.contains($0) ? $0 : nil }
        self.directory = directory
        hosted = HostedAccount(preferences: preferences, production: preferences === UserDefaults.standard && Bundle.main.bundleIdentifier == "app.saytile.mac")
        self.preferences = preferences
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
        floatingEntryEnabled = preferences.bool(forKey: "floatingEntryEnabled")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        shortcutChoice = preferences.string(forKey: "shortcutChoice") ?? "option-space"
        audio.selectDevice(uid: preferences.string(forKey: "selectedDeviceUID"))
        deviceID = audio.selectedDeviceUID != nil && audio.selectedDeviceID == 0 ? UInt32.max : audio.selectedDeviceID
        initializing = false
        hosted.bind { [weak self] route, revoke in
            guard let self else { return }
            accountRoute = route
            audio.selectHostedRoute(deviceOnly ? .local : route, revoke: revoke)
            objectWillChange.send()
        }
        applyLocalSelection()
        Task { await refreshLocalRecommendation() }
        input.onBindingInvalidated = { [weak self] in
            self?.directMode = false
            self?.targetLabel = "目标已改变，请重新绑定草稿"
            self?.notice = "自动输入已暂停，新内容继续保留在 Saytile。"
        }
        subscription = audio.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in guard let self else { return }
                self.objectWillChange.send()
                if let uid = self.audio.selectedDeviceUID {
                    let resolved = self.audio.devices.first(where: { $0.uid == uid })?.id ?? UInt32.max
                    if self.deviceID != resolved { self.initializing = true; self.deviceID = resolved; self.initializing = false }
                }
                if case .interrupted = self.audio.state, self.input.binding != nil { self.input.invalidate() } }
        }
        recognitionSubscription = NotificationCenter.default.publisher(for: .init("SaytileRecognitionUpdated"))
            .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in Task { @MainActor [weak self] in await self?.refresh() } }
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
            measuredLevel: captureDependencies.level(audio))
    }
    var panelCaptureLabel: String { panelCapturePresentation.label }
    var panelCaptureDetail: String? { panelCapturePresentation.detail }
    var captureActionLabel: String { panelCapturePresentation.actionLabel }
    var captureActionSymbolName: String { panelCapturePresentation.actionSymbolName }
    var captureLabel: String { panelCaptureLabel }
    var captureProblem: Bool { if case .interrupted = captureDependencies.state(audio) { return true }; return false }
    var saveLabel: String { captureProblem ? "收音已暂停 · 请查看保存状态" : isListening ? "原音独立保存 · 识别不会阻塞收音" : "内容保存在此 Mac，随时可以取用" }
    var microphoneLabel: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
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
    func selectSource(_ source: String) {
        if source != "local" && localTextAllowed { allowLocalText(false) }
        deviceOnly = source == "local"
        preferences.set(deviceOnly, forKey: "localASR.deviceOnly")
        hosted.select(source == "hosted")
        audio.selectHostedRoute(deviceOnly ? .local : accountRoute)
        audio.refreshLocalModelStatus()
    }
    func selectLocal(_ model: LocalASRID?, archiveOnly: Bool = false) {
        if archiveOnly {
            archiveLocalModel = model
            preferences.set(model?.rawValue, forKey: "localASR.archive")
        } else {
            guard model?.capability != .batch else { return }
            manualLocalModel = model
            preferences.set(model?.rawValue, forKey: "localASR.manual")
        }
        applyLocalSelection()
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
        guard manualLocalModel == nil else { return }
        let sherpa = await localModels.library.status(.sherpa)
        let apple = await AppleSpeechService.availability()
        let pick = LocalModelRecommendation.select(appleInstalled: apple.installed, sherpaInstalled: sherpa.installed)
        guard manualLocalModel == nil, pick != automaticLocal else { return }
        automaticLocal = pick
        applyLocalSelection()
    }
    func applyLocalSelection() {
        if deviceOnly, localTextAllowed, localReview == nil, let item = localGPT { localReview = LocalTextReview(model: item) }
        let live = manualLocalModel ?? automaticLocal
        audio.selectLocalModels(live: live, archive: archiveLocalModel ?? live, service: localModels, review: localReview)
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
            if changingRoute && candidate.cloudEnabled {
                connectionDependencies.applyNextRoute(audio, candidate)
                appliedRecognitionConfiguration = candidate
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
                recognitionSettingsNotice = candidate.cloudEnabled ? "设置已应用。采集与原音保存继续独立运行。" : "已停止云端识别，继续使用本机模型。"
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
    func checkRecognitionConnections() {
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
                    recognitionConfiguration.cloudEnabled = true
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
        var choices = [DisplayDevice(id: 0, name: "系统默认输入设备")] + audio.devices.map { DisplayDevice(id: $0.id, name: $0.name) }
        if deviceID == UInt32.max { choices.append(DisplayDevice(id: UInt32.max, name: "已选择的麦克风未连接")) }
        return choices
    }
    var playingID: UUID? { audio.playingID }
    func toggleCapture() {
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
            objectWillChange.send()
            if let issue = audio.issue { notice = issue }
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
        timelineRead &+= 1
        let request = timelineRead
        let page = try await store.timelinePage(window)
        let tail = window == .latest ? page.entries.last : try await store.timelinePage().entries.last
        guard window == timelineWindow, request == timelineRead else { return }
        if timeline != page { timeline = page }
        if timelineTail != tail { timelineTail = tail }
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

    func copyTimeline(selection: String, displayed: [Int64: String]) {
        if !selection.isEmpty { copy(selection, quietly: true); return }
        guard let end = timelineTail else { return }
        // The editor can hold a previous page across a new group. The click targets
        // the live tail while preserving the exact text of any already rendered rows.
        var snapshot = Dictionary(uniqueKeysWithValues: timeline.entries.map { ($0.position, $0.recording.text) })
        snapshot[end.position] = end.recording.text
        snapshot.merge(displayed) { _, rendered in rendered }
        do { copy(try store.timelineCopy(group: end.group, through: end.position, displayed: snapshot), quietly: true) }
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
    func copyRecent() { copy(recent.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")) }
    func loadEarlierPanel() {
        guard !loadingPanel else { return }
        panelLimit += 100; refreshVersion &+= 1; loadingPanel = true
        Task { await refresh(); loadingPanel = false }
    }
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
                _ = try await input.bindCurrentTarget(purpose: .manual)
                var frozen: [TranscriptRevision] = []
                for snapshot in snapshots {
                    frozen.append(try await store.freezeRevision(recordingID: snapshot.recordingID, revisionID: snapshot.revisionID, text: snapshot.text))
                }
                for snapshot in frozen {
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
            editorDraftStatus = pendingDraftWrites[item.id] == nil ? "修改会自动暂存，保存后更新这段文字" : "草稿尚未写入磁盘，请保留此窗口"
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
                if editorRecordingID == item.id { editorWasEdited = false; editorDraftStatus = "修改已保存" }
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
        editorDebounce?.cancel()
        _ = await flushEditorDrafts()
        // If saving fails, the delegate keeps this window open and the normal refresh loop alive.
        if !hasUnpersistedDrafts {
            exitPrepared = true
            timer?.cancel(); refreshTask?.cancel()
            await audio.shutdown()
            await refreshOperation?.value
            do { try await store.close() } catch { notice = error.localizedDescription }
        } else { startRefreshTimer() }
    }
    // All callers await the same in-flight refresh, including startup diagnostics.
    // A timer refresh must not make a user action or initial render return empty early.
    func refresh() async {
        guard !exitPrepared else { return }
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
                operation = Task<Void, Never> { [weak self] in
                    guard let self else { return }
                    await self.performRefresh()
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
            var rows: [Recording] = []
            while rows.count < requestedLimit + 1 {
                let batch = try await store.listRecordings(query: requestedQuery, limit: min(100, requestedLimit + 1 - rows.count), offset: rows.count, filter: requestedFilter)
                rows += batch
                if batch.isEmpty { break }
            }
            guard query == requestedQuery, recordFilter == requestedFilter, pageLimit == requestedLimit else { scheduleRefresh(); return }
            hasMore = rows.count > requestedLimit
            let nextRecords = Array(rows.prefix(requestedLimit)).map { DisplayRecording(source: $0) }
            if records != nextRecords { records = nextRecords }
            let panelStart = panelSessionStartedAt, panelIDs = Array(stagedRecordIDs), requestedPanelLimit = panelLimit
            var panelRows: [Recording] = []
            while panelRows.count < requestedPanelLimit {
                let batch = try await store.listPanelRecordings(createdSince: panelStart, includingIDs: panelIDs, limit: min(100, requestedPanelLimit - panelRows.count), offset: panelRows.count)
                panelRows += batch
                if batch.isEmpty { break }
            }
            let total = try await store.panelRecordingCount(createdSince: panelStart, includingIDs: panelIDs)
            if panelStart == panelSessionStartedAt, Set(panelIDs) == stagedRecordIDs, requestedPanelLimit == panelLimit {
                panelCount = total; panelHasMore = panelRows.count < total
                let nextRecent = panelRows.reversed().map { DisplayRecording(source: $0) }
                if recent != nextRecent { recent = nextRecent }
            }
            if let selection = selected {
                let refreshedSelection = try await store.recording(id: selection.id).map { DisplayRecording(source: $0) }
                if selected?.id == selection.id {
                    if selected != refreshedSelection { selected = refreshedSelection }
                    if editorRecordingID == selection.id, !editorWasEdited, let refreshedSelection { editorDraft = refreshedSelection.text }
                    if refreshedSelection?.source.preferredRevisionID != selection.source.preferredRevisionID { await loadVersions(selection.id) }
                }
            }
            if Date.now.timeIntervalSince(lastModelCallRefresh) > 2 {
                lastModelCallRefresh = Date.now
                modelCallSummary = try await store.modelCallSummaries(limit: 30)
            }
            if Date.now.timeIntervalSince(lastStorageRefresh) > 60 {
            lastStorageRefresh = Date.now
            let summary = try await store.storageSummary()
            storageLabel = ByteCountFormatter.string(fromByteCount: summary.audioBytes, countStyle: .file)
            if summary.shouldWarn { notice = "原音空间已达到提醒阈值，或磁盘剩余不足 1 GB。请在设置中查看存储。" }
            }
            let visibleIDs = Set(records.map(\.id) + recent.map(\.id))
            insertionLabels = insertionLabels.filter { visibleIDs.contains($0.key) }
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
    private func setLoginItem() {
        guard !initializing else { return }
        do { if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { notice = "登录启动未能更新：\(error.localizedDescription)" }
        let status = SMAppService.mainApp.status
        if status == .requiresApproval { notice = "登录启动需要在系统设置的登录项中允许。收音仍需你主动开启。" }
        initializing = true; launchAtLogin = status == .enabled; initializing = false
    }
}

private enum MultiConnectionMessage {
    static func safe(_ error: Error) -> String {
        if let known = error as? ProviderFailure { return known.localizedDescription }
        if let known = error as? CloudCredentialError { return known.localizedDescription }
        return "连接检查未完成，请稍后重试。本机识别可以继续使用。"
    }
}
