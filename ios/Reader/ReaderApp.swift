import AVFoundation
import CloudKit
import SwiftUI

extension PrivateArchive {
    var readingText: String { draft?.text ?? versions.first(where: { $0.id == head })?.text ?? "" }
}
@MainActor final class ReaderModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var rows: [PrivateArchive] = []
    @Published private(set) var status = "正在读取语音档案"
    @Published private(set) var playing: UUID?
    @Published private(set) var loading: UUID?
    @Published var query = ""
    private let source: (any ReaderSource)?
    private let disk: ReaderDisk
    private let fixture: Bool
    private var owner: String?
    private var activeIdentity: String?
    private var session = UUID(), playback = UUID()
    private var player: AVAudioPlayer?, remaining: [URL] = []
    private var syncing = false
    override init() {
        #if DEBUG && targetEnvironment(simulator)
        fixture = ProcessInfo.processInfo.arguments.contains("--public-reader-fixture")
        #else
        fixture = false
        #endif
        if fixture { source = SampleReader() }
        else {
            #if SAYTILE_READER_DEVELOPMENT && os(iOS) && !targetEnvironment(simulator)
            source = ReaderCloud()
            #else
            source = nil
            #endif
        }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        disk = ReaderDisk(root: root.appendingPathComponent(fixture ? "ReaderFixture" : "SaytileArchive"))
        super.init()
    }
    private var identity: String? {
        if fixture { return "fixture" }
        guard let token = FileManager.default.ubiquityIdentityToken,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false) else { return nil }
        return ArchiveCloudRecord.digest(data)
    }
    private func display(_ state: ReaderSnapshot) {
        rows = state.rows.values.filter { !$0.deleted }.sorted { ($0.group.start,$0.started,$0.id.uuidString) > ($1.group.start,$1.started,$1.id.uuidString) }
        if let id = playing ?? loading, state.rows[id]?.chunks.isEmpty != false { stop() }
    }
    func accountChanged() {
        session = UUID(); stop(); owner = nil; activeIdentity = nil; rows = []; syncing = false
    }
    func refresh() async {
        guard let source else { status = "此候选尚未连接 iCloud"; return }
        if activeIdentity != identity { accountChanged(); activeIdentity = identity }
        guard !syncing else { return }
        syncing = true
        let generation = session, identity = self.identity
        defer { if session == generation { syncing = false } }
        do {
            if owner == nil, let identity, let cached = UserDefaults.standard.string(forKey: "reader.owner." + identity) {
                let state = try await disk.load(cached)
                guard session == generation, self.identity == identity else { return }
                owner = cached; display(state)
            }
            let key = try await source.owner()
            guard session == generation, self.identity == identity else { return }
            if owner != key { stop(); rows = [] }
            owner = key
            if let identity { UserDefaults.standard.set(key, forKey: "reader.owner." + identity) }
            var state = try await disk.load(key)
            guard session == generation else { return }
            display(state)
            var rebuilding = false
            while true {
                let page: ReaderPage
                do { page = try await source.page(owner: key, after: state.cursor) }
                catch ArchiveIssue.cursorExpired where !rebuilding { state = .init(); rebuilding = true; continue }
                guard session == generation, self.identity == identity else { return }
                for item in page.items { try item.validate(); state.rows[item.id] = item.deleted ? nil : item }
                for id in page.removed { state.rows[id] = nil }
                state.cursor = page.next
                if !rebuilding || !page.more {
                    try await disk.save(state, key: key)
                    guard session == generation else { return }
                    display(state)
                }
                if !page.more { break }
            }
            status = rows.isEmpty ? "还没有已同步的档案" : ""
        } catch ArchiveIssue.accountChanged { if session == generation { accountChanged(); status = "Apple 账户已更改" } }
        catch {
            if session == generation {
                let transient = (error as? CKError).map { [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .notAuthenticated].contains($0.code) } ?? false
                status = (error as? ArchiveIssue) == .unavailable || transient ? "等待 iCloud · 可阅读已下载的档案" : "未能更新档案 · 将自动重试"
            }
        }
    }
    func stop() { playback = UUID(); player?.stop(); player = nil; remaining = []; playing = nil; loading = nil }
    func listen(_ item: PrivateArchive) async {
        if playing == item.id || loading == item.id { stop(); return }
        stop()
        guard let source, let owner, !item.chunks.isEmpty, !item.deleted, !item.audioDeleted else { return }
        let generation = playback
        loading = item.id
        do {
            let parts = try await disk.parts(item, owner: owner, source: source)
            guard playback == generation, rows.first(where: { $0.id == item.id })?.chunks == item.chunks else { return }
            remaining = parts; playing = item.id; loading = nil
            try next()
        } catch { if playback == generation { stop(); status = "暂时无法回听这段原音" } }
    }
    private func next() throws {
        guard !remaining.isEmpty else { stop(); return }
        let audio = try AVAudioPlayer(contentsOf: remaining.removeFirst())
        audio.delegate = self; player = audio
        guard audio.prepareToPlay(), audio.play() else { throw ArchiveIssue.invalid }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully success: Bool) {
        let id = ObjectIdentifier(finished)
        Task { @MainActor in
            guard let current = player, ObjectIdentifier(current) == id else { return }
            do { guard success else { throw ArchiveIssue.invalid }; try next() }
            catch { stop(); status = "无法继续回听原音" }
        }
    }
}

@main struct SaytileReaderApp: App {
    @StateObject private var model = ReaderModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    if !model.status.isEmpty { Text(model.status).font(.footnote).foregroundStyle(.secondary) }
                    ForEach(model.rows.filter { model.query.isEmpty || $0.readingText.localizedCaseInsensitiveContains(model.query) }, id: \.id) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(Date(timeIntervalSince1970: item.started), format: .dateTime.month().day().hour().minute())
                                if item.pinned { Image(systemName: "star.fill").foregroundStyle(.purple).accessibilityLabel("已收藏") }
                                Spacer()
                                if item.chunks.isEmpty { Text(item.audioDeleted ? "原音已删除" : "尚无原音") }
                                else {
                                    let title = model.playing == item.id ? "停止回听" : (model.loading == item.id ? "取消下载" : "回听")
                                    Button { Task { await model.listen(item) } } label: {
                                        Label(title, systemImage: model.playing == item.id ? "stop.fill" : "play.fill")
                                    }.buttonStyle(.borderless).accessibilityLabel(title)
                                }
                            }.font(.caption).foregroundStyle(.secondary)
                            Text(item.readingText.isEmpty ? "尚未转写" : item.readingText).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 6)
                    }
                }.listStyle(.plain).navigationTitle("语音档案").searchable(text: $model.query, prompt: "搜索文字")
                    .refreshable { await model.refresh() }
            }
            .tint(.purple)
            .task(id: phase) {
                guard phase == .active else { return }
                while !Task.isCancelled { await model.refresh(); do { try await Task.sleep(for: .seconds(60)) } catch { return } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                model.accountChanged(); Task { await model.refresh() }
            }
        }
    }
}
