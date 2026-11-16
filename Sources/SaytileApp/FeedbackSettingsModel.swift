import AppKit
import SwiftUI
import RiftletFeedback

/// Feedback has its own durable outbox and capabilities, never the audio archive or API keys.
@MainActor final class FeedbackSettingsModel: ObservableObject {
    @Published private(set) var draft = FeedbackDraft()
    @Published private(set) var records: [FeedbackRecord] = []
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var closing = false
    @Published private(set) var message: String?
    private(set) var hasUnsavedDraft = false
    private var engine: FeedbackEngine?
    private var loading: Task<Void, Never>?
    private var saving: Task<Void, Never>?
    private var sending: Task<Void, Never>?
    private let version: String
    static let endpoint = URL(string: "https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback")!

    init(directory: URL, normalLaunch: Bool, transport: (any FeedbackTransport)? = nil,
         secrets: (any FeedbackSecretStorage)? = nil) {
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        loading = Task { [weak self] in
            do {
                let store = try await Task.detached(priority: .utility) {
                    try FeedbackStore(directory: directory.appendingPathComponent("Feedback-v01"))
                }.value
                guard let self else { return }
                let network: any FeedbackTransport = try transport ?? (normalLaunch
                    ? HTTPSFeedbackTransport(endpoint: Self.endpoint) : DisabledFeedbackTransport())
                let credentials: any FeedbackSecretStorage = secrets ?? (normalLaunch
                    ? KeychainFeedbackSecrets(namespace: (Bundle.main.bundleIdentifier ?? "app.saytile.mac") + ".feedback") : MemoryFeedbackSecrets())
                let engine = FeedbackEngine(store: store, secrets: credentials, transport: network)
                self.engine = engine
                self.draft = try await store.draft()
                self.ready = true
                await self.reload()
                // Only explicit, previously queued submissions are allowed to send.
                Task { [weak self] in await engine.pump(); await self?.reload() }
            } catch { self?.message = "反馈暂时不可用；录音和文字保存不受影响。" }
        }
    }
    var canSend: Bool { ready && !busy && !closing && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.text.unicodeScalars.count <= 4000 && draft.text.utf8.count <= 16384 }
    func edit(text: String? = nil, kind: FeedbackKind? = nil) {
        guard ready, !busy, !closing, draft.revision < Int64.max - 1 else { return }
        if let text { draft.text = text }
        if let kind { draft.kind = kind }
        draft.revision += 1; hasUnsavedDraft = true
        let value = draft, prior = saving
        saving = Task { [weak self] in
            await prior?.value
            guard let self, let engine = self.engine else { return }
            do {
                try await engine.store.saveDraft(value)
                if self.draft.revision == value.revision { self.hasUnsavedDraft = false }
            } catch { self.message = "反馈草稿尚未保存，请保留窗口后重试。" }
        }
    }
    func send() {
        guard canSend, let engine else { return }
        busy = true; message = nil
        let snapshot = draft
        sending = Task { [weak self] in
            guard let self else { return }
            await self.saving?.value
            do {
                _ = try await engine.enqueue(snapshot, appVersion: self.version, product: .saytile)
                self.draft = try await engine.store.draft(); self.hasUnsavedDraft = false
                self.message = "已保存反馈，联网后会自动发送。"
                self.busy = false
                await self.reload()
                Task { [weak self] in await engine.pump(); await self?.reload() }
            } catch {
                self.message = "暂时无法发送，草稿仍保留在这里。请稍后重试。"; self.busy = false
            }
        }
    }
    func reload() async { if let engine { do { records = try await engine.store.records() } catch { message = "暂时无法读取反馈记录。" } } }
    func refresh(_ record: FeedbackRecord) async {
        guard !closing, let engine else { return }
        do { try await engine.refresh(id: record.id); message = nil }
        catch { message = "暂时无法确认送达状态，反馈记录已保留。" }
        await reload()
    }
    func withdraw(_ record: FeedbackRecord) async {
        guard !closing, let engine else { return }
        do { try await engine.requestDeletion(id: record.id); message = nil }
        catch { message = "撤回申请尚未完成，请稍后查看状态。" }
        await reload()
    }
    func forget(_ record: FeedbackRecord) async {
        guard !closing, let engine else { return }
        do { try await engine.forgetResolved(id: record.id) }
        catch { message = "暂时无法移除此条反馈。" }
        await reload()
    }
    func prepareForExit() async {
        closing = true
        await loading?.value
        await saving?.value
        // Wait only for the durable local enqueue, never for a network response.
        await sending?.value
        if hasUnsavedDraft, let engine {
            do { try await engine.store.saveDraft(draft); hasUnsavedDraft = false }
            catch { message = "反馈草稿尚未保存，请重试后再退出。"; return }
        }
    }
    func cancelExit() { closing = false }
    func finishExit() async {
        await engine?.stop()
        try? await engine?.store.markClean()
    }
}

