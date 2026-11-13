import AVFoundation
import Foundation

// Compile together with the actual iPhone reader sources on macOS. This probe
// never constructs ReaderCloud or accesses an application cache or Apple ID.
private actor ProbeSource: ReaderSource {
    let key: String
    let wav: URL
    private(set) var fetches = 0
    var beforeReturn: (@Sendable () async throws -> Void)?
    func duringFetch(_ block: @escaping @Sendable () async throws -> Void) { beforeReturn = block }
    init(key: String, wav: URL) { self.key = key; self.wav = wav }
    func owner() -> String { key }
    func page(owner: String, after: Data?) throws -> ReaderPage { throw ArchiveIssue.invalid }
    func audio(owner: String, item: PrivateArchive) async throws -> [URL] {
        guard owner == key else { throw ArchiveIssue.accountChanged }
        fetches += 1
        try await beforeReturn?()
        return [wav]
    }
}
private enum Failure: Error { case expected(String) }
private func check(_ passed: Bool, _ name: String) throws {
    guard passed else { throw Failure.expected(name) }
    print("PASS " + name)
}
private func makeWAV() -> Data {
    var result = Data("RIFF".utf8)
    func little<T: FixedWidthInteger>(_ x: T) { withUnsafeBytes(of: x.littleEndian) { result.append(contentsOf: $0) } }
    let n = 1600
    little(UInt32(36+2*n)); result.append(Data("WAVEfmt ".utf8)); little(UInt32(16)); little(UInt16(1)); little(UInt16(1))
    little(UInt32(16000)); little(UInt32(32000)); little(UInt16(2)); little(UInt16(16)); result.append(Data("data".utf8)); little(UInt32(2*n))
    for i in 0..<n { little(Int16(32*(i%16))) }
    return result
}
private func makeItem(_ digest: String) -> PrivateArchive {
    let v = PrivateArchive.Version(id: UUID(),text: "隔离阅读记录",origin: .final,created: 1,attempt: nil,base: nil)
    return PrivateArchive(format: 1,id: UUID(),started: 1,ended: 2,day: "2001-01-01",offset: 0,group: .init(start: 1,day: "2001-01-01",offset: 0),
        sampleRate: 16000,head: v.id,pinned: false,deleted: false,audioDeleted: false,versions: [v],chunks: [.init(id: UUID(),frames: 1600,ordinal: 0,sha256: digest)])
}
@main struct ReaderDiskProbe {
    static func main() async {
        do { try await run() }
        catch {
            print("FAIL \(error)")
            exit(1)
        }
    }
    private static func run() async throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("saytile-reader-disk-" + UUID().uuidString,isDirectory: true)
        try fm.createDirectory(at: scratch,withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: scratch) }
        let a = ArchiveCloudRecord.ownerKey("fixture-owner-a"), b = ArchiveCloudRecord.ownerKey("fixture-owner-b")
        let pcm = makeWAV(), wav = scratch.appendingPathComponent("source.wav")
        let digest = ArchiveCloudRecord.digest(pcm)
        try pcm.write(to: wav)
        let disk = ReaderDisk(root: scratch.appendingPathComponent("cache")), sa = ProbeSource(key: a,wav: wav), sb = ProbeSource(key: b,wav: wav)
        var item = makeItem(digest)
        try item.validate()
        var state = ReaderSnapshot(cursor: Data([1]),rows: [item.id: item])
        try await disk.save(state,key: a)
        try check(await sa.fetches == 0, "metadata synchronization does not fetch audio")
        let parts = try await disk.parts(item,owner: a,source: sa)
        let file = try AVAudioFile(forReading: parts[0])
        try check(try await sa.fetches == 1 && file.length == 1600 && Data(contentsOf: parts[0]) == pcm, "on-demand fetch verifies and decodes 1600 frames")
        let second = try await disk.parts(item,owner: a,source: sa)
        try check(await sa.fetches == 1 && second == parts, "verified cache hit uses no network")
        var damaged = pcm; damaged[damaged.count-1] ^= 1
        try damaged.write(to: parts[0]); try damaged.write(to: wav)
        do { _ = try await disk.parts(item,owner: a,source: sa); throw Failure.expected("rejected corruption") }
        catch ArchiveIssue.invalid {}
        try check(await sa.fetches == 2, "equal-size corrupt cached and remote assets rejected")
        try pcm.write(to: wav)
        let repaired = try await disk.parts(item,owner: a,source: sa)
        try check(try await sa.fetches == 3 && Data(contentsOf: repaired[0]) == pcm, "verified replacement repairs corrupted cache")
        let empty = try await disk.load(b)
        try check(empty.rows.isEmpty && empty.cursor == nil, "second account cannot read predecessor metadata or cursor")
        try await disk.save(state,key:b)
        let isolated = try await disk.parts(item,owner:b,source:sb)
        try check(await sb.fetches == 1 && isolated[0] != repaired[0], "second account fetches into a distinct folder even for identical SHA")
        let sameAudio = makeItem(digest)
        state.rows[sameAudio.id] = sameAudio
        item.audioDeleted = true; item.chunks = []
        state.rows[item.id] = item
        try await disk.save(state,key:a)
        let loaded = try await disk.load(a)
        try check(loaded.rows[item.id]?.audioDeleted == true && loaded.rows[item.id]?.versions == item.versions, "original-only erasure retains transcript and revisions")
        guard let old = try await disk.load(b).rows[item.id] else { throw Failure.expected("old snapshot") }
        var refused = false
        do { _ = try await disk.parts(old,owner:a,source:sa) } catch ArchiveIssue.stale { refused = true }
        print(refused ? "PASS stale cache hit denied after deletion with identical live asset" : "FAIL stale cache hit served a deleted recording's still-shared bytes")
        let stillOwned = try await disk.parts(sameAudio,owner: a,source: sa)
        try check(try await sa.fetches == 3 && Data(contentsOf: stillOwned[0]) == pcm, "other live owner of the same WAV remains playable")
        state.rows[sameAudio.id] = nil; state.rows[item.id] = nil
        try await disk.save(state,key:a)
        try check(!fm.fileExists(atPath: repaired[0].path) && fm.fileExists(atPath: isolated[0].path), "last reference deletion prunes only that owner's WAV")
        try check(try await disk.load(a).rows.isEmpty, "record erasure persists after reopening")
        let active = makeItem(digest)
        try await disk.save(.init(cursor: nil,rows: [active.id:active]),key: a)
        try? fm.removeItem(at: repaired[0])
        await sa.duringFetch { try await disk.save(.init(),key:a) }
        do { _ = try await disk.parts(active,owner:a,source:sa); throw Failure.expected("late download after deletion") }
        catch ArchiveIssue.stale {}
        try check(!fm.fileExists(atPath: repaired[0].path), "deleted in-flight download cannot reinstall or return its bytes")
        print("fixture_wav_bytes=\(pcm.count) fixture_sha256=\(digest) real_service_calls=0")
        if !refused { throw Failure.expected("stale cache hit") }
    }
}
