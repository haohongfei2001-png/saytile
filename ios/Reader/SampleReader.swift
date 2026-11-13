#if DEBUG && targetEnvironment(simulator)
import Foundation

// Only instantiated by an explicit Debug simulator launch. No CloudKit account.
struct SampleReader: ReaderSource {
    private static let record = UUID(uuidString: "80E534FA-8C9F-4DB1-BF0B-4F619720910E")!
    private static let version = UUID(uuidString: "C7EB898F-3A10-400D-A867-F8EAE7086D13")!
    private static let chunk = UUID(uuidString: "009F1F92-2CCB-47DF-8B5A-9650910156C2")!
    static let text = "星期五下午三点，讨论原音备份。"
    func owner() async throws -> String { ArchiveCloudRecord.ownerKey("isolated-simulator-fixture") }
    private var wav: Data {
        var d = Data("RIFF".utf8)
        func le<T: FixedWidthInteger>(_ n: T) { withUnsafeBytes(of: n.littleEndian) { d.append(contentsOf: $0) } }
        let frames = 48_000
        le(UInt32(36 + frames * 2)); d.append(Data("WAVEfmt ".utf8)); le(UInt32(16)); le(UInt16(1)); le(UInt16(1))
        le(UInt32(16000)); le(UInt32(32000)); le(UInt16(2)); le(UInt16(16)); d.append(Data("data".utf8)); le(UInt32(frames * 2))
        for i in 0..<frames { le(Int16((i % 80 - 40) * 8)) }
        return d
    }
    func page(owner: String, after: Data?) async throws -> ReaderPage {
        let item = PrivateArchive(format: 1, id: Self.record, started: 1_760_000_000, ended: 1_760_000_003,
            day: "2025-10-09", offset: 0, group: .init(start: 1_760_000_000, day: "2025-10-09", offset: 0),
            sampleRate: 16000, head: Self.version, pinned: true, deleted: false, audioDeleted: false,
            versions: [.init(id: Self.version, text: Self.text, origin: .userEdit, created: 1_760_000_004, attempt: nil, base: nil)],
            chunks: [.init(id: Self.chunk, frames: 48000, ordinal: 0, sha256: ArchiveCloudRecord.digest(wav))])
        return ReaderPage(items: after == nil ? [item] : [], removed: [], next: Data([1]), more: false)
    }
    func audio(owner: String, item: PrivateArchive) async throws -> [URL] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-public-reader-fixture.wav")
        try wav.write(to: url, options: .atomic); return [url]
    }
}

#endif
