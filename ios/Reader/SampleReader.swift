#if DEBUG && targetEnvironment(simulator)
import Foundation

// Only instantiated by an explicit Debug simulator launch. No CloudKit account.
struct SampleReader: ReaderSource {
    private static let record = UUID(uuidString: "80E534FA-8C9F-4DB1-BF0B-4F619720910E")!
    private static let version = UUID(uuidString: "C7EB898F-3A10-400D-A867-F8EAE7086D13")!
    private static let chunk = UUID(uuidString: "009F1F92-2CCB-47DF-8B5A-9650910156C2")!
    static let seconds = 6
    static let frames = seconds * 16_000
    func owner() async throws -> String { ArchiveCloudRecord.ownerKey("isolated-simulator-fixture") }
    private var wav: Data {
        var d = Data("RIFF".utf8)
        func le<T: FixedWidthInteger>(_ n: T) { withUnsafeBytes(of: n.littleEndian) { d.append(contentsOf: $0) } }
        let frames = Self.frames
        le(UInt32(36 + frames * 2)); d.append(Data("WAVEfmt ".utf8)); le(UInt32(16)); le(UInt16(1)); le(UInt16(1))
        le(UInt32(16000)); le(UInt32(32000)); le(UInt16(2)); le(UInt16(16)); d.append(Data("data".utf8)); le(UInt32(frames * 2))
        for i in 0..<frames { le(Int16((i % 80 - 40) * 8)) }
        return d
    }
    func page(owner: String, after: Data?) async throws -> ReaderPage {
        let start = 1_760_000_000.0
        let paragraph = PrivateArchive.Paragraph(id: Self.record, start: start, day: "2025-10-09", offset: 0, hidden: false, edited: 0)
        let ids = [Self.record, UUID(uuidString: "72016381-A0E1-464A-84F9-C2937F061BAD")!]
        let texts = ["星期五下午三点，","讨论原音备份。"]
        let versions = [Self.version, UUID(uuidString: "5AB50738-8A9C-4B29-9CFE-F4C263DAC33F")!]
        let chunks = [Self.chunk, UUID(uuidString: "4A1065C2-5B63-45CB-83D5-F85B2211A214")!]
        let digest = ArchiveCloudRecord.digest(wav)
        let items = ids.indices.map { i in
            let began = start + Double(i) * Double(Self.seconds)
            return PrivateArchive(format: 1, id: ids[i], started: began, ended: began + Double(Self.seconds),
                day: "2025-10-09", offset: 0, group: .init(start: start, day: "2025-10-09", offset: 0),
                sampleRate: 16000, sequence: Int64(i+1), paragraph: paragraph, head: versions[i], pinned: true, deleted: false, audioDeleted: false,
                versions: [.init(id: versions[i], text: texts[i], origin: .userEdit, created: began, attempt: nil, base: nil)],
                chunks: [.init(id: chunks[i], frames: Int64(Self.frames), ordinal: 0, sha256: digest)])
        }
        return ReaderPage(items: after == nil ? Array(items.reversed()) : [], removed: [], next: Data([1]), more: false)

    }
    func audio(owner: String, item: PrivateArchive) async throws -> [URL] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-public-reader-fixture.wav")
        try wav.write(to: url, options: .atomic); return [url]
    }
}

#endif
