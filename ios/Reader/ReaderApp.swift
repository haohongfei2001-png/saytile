import AVFoundation
import CloudKit
import SwiftUI

@MainActor final class ReaderModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var rows: [ReaderParagraph] = []
    private var currentArchive: [UUID: PrivateArchive] = [:]
    private var playlist: [PrivateArchive] = []
    private var playbackChunks: [UUID: [PrivateArchive.Chunk]] = [:]
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
        #if DEBUG && targetEnvironment(simulator)
        source = fixture ? SampleReader() : nil
        #elseif SAYTILE_READER_DEVELOPMENT && os(iOS) && !targetEnvironment(simulator)
        source = ReaderCloud()
        #else
        source = nil
        #endif
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
        currentArchive = state.rows
        rows = ReaderParagraph.assemble(Array(state.rows.values))
        if playbackChunks.contains(where: { state.rows[$0.key]?.chunks != $0.value }) { stop() }
    }
    func accountChanged() {
        session = UUID(); stop(); owner = nil; activeIdentity = nil; rows = []; currentArchive = [:]; syncing = false
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
            if owner != key { stop(); rows = []; currentArchive = [:] }
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
                status = (error as? ArchiveIssue) == .unavailable || transient ? (rows.isEmpty ? "等待 iCloud" : "等待 iCloud · 可阅读已下载的档案") : "未能更新档案 · 将自动重试"
            }
        }
    }
    func stop() {
        playback = UUID(); player?.stop(); player = nil; remaining = []; playlist = []; playbackChunks = [:]
        playing = nil; loading = nil
    }
    func listen(_ paragraph: ReaderParagraph) async {
        if playing == paragraph.id || loading == paragraph.id { stop(); return }
        stop()
        playlist = paragraph.playable
        guard !playlist.isEmpty else { return }
        playbackChunks = Dictionary(uniqueKeysWithValues: playlist.map { ($0.id, $0.chunks) })
        let generation = playback
        loading = paragraph.id
        do { try await next(id: paragraph.id, generation: generation) }
        catch { if playback == generation { stop(); status = "暂时无法回听这段原音" } }
    }
    private func next(id: UUID, generation: UUID) async throws {
        guard playback == generation else { return }
        if remaining.isEmpty {
            guard !playlist.isEmpty, let source, let owner else { stop(); return }
            let record = playlist.removeFirst()
            let parts = try await disk.parts(record, owner: owner, source: source)
            guard playback == generation else { return }
            guard currentArchive[record.id]?.chunks == record.chunks else { throw ArchiveIssue.stale }
            remaining = parts
        }
        guard !remaining.isEmpty else { throw ArchiveIssue.invalid }
        let audio = try AVAudioPlayer(contentsOf: remaining.removeFirst())
        audio.delegate = self; player = audio
        guard audio.prepareToPlay(), audio.play() else { throw ArchiveIssue.invalid }
        playing = id; loading = nil
    }
    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully success: Bool) {
        let id = ObjectIdentifier(finished)
        Task { @MainActor in
            guard let current = player, ObjectIdentifier(current) == id else { return }
            guard let paragraph = playing else { return }
            let generation = playback
            do { guard success else { throw ArchiveIssue.invalid }; try await next(id: paragraph, generation: generation) }
            catch { if generation == playback { stop(); status = "无法继续回听原音" } }
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
                    ForEach(model.rows.filter { $0.match(model.query) != nil }, id: \.id) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(Date(timeIntervalSince1970: item.started), format: .dateTime.month().day().hour().minute())
                                if item.pinned { Image(systemName: "star.fill").foregroundStyle(.purple).accessibilityLabel("已收藏") }
                                Spacer()
                                if item.playable.isEmpty { Text(item.members.allSatisfy(\.audioDeleted) ? "原音已删除" : "尚无原音") }
                                else {
                                    let title = model.playing == item.id ? "停止回听" : (model.loading == item.id ? "取消下载" : "回听")
                                    Button { Task { await model.listen(item) } } label: {
                                        Label(title, systemImage: model.playing == item.id ? "stop.fill" : "play.fill")
                                    }.buttonStyle(.borderless).accessibilityLabel(title)
                                }
                            }.font(.caption).foregroundStyle(.secondary)
                            let shown = item.match(model.query) ?? item.text
                            if shown != item.text { Text("历史版本").font(.caption).foregroundStyle(.secondary) }
                            #if os(iOS)
                            if shown.isEmpty { Text("尚未转写").foregroundStyle(.secondary) }
                            else { SelectableTranscript(text: shown).frame(maxWidth: .infinity, alignment: .leading) }
                            #else
                            Text(shown.isEmpty ? "尚未转写" : shown).textSelection(.enabled)
                            #endif
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
