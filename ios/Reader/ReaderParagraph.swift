import Foundation

extension PrivateArchive {
    var readingOrder: (Int64, Double, String) { (sequence ?? 0, started, id.uuidString) }
    var readingText: String { draft?.text ?? versions.first(where: { $0.id == head })?.text ?? "" }
}

/// Preserve the Mac's paragraph ownership even when CloudKit delivers the
/// recordings in separate pages. Older manifests remain individual entries.
struct ReaderParagraph: Identifiable {
    let id: UUID
    let started: Double
    var members: [PrivateArchive]

    var text: String { VoiceTranscriptFlow.join(members.map(\.readingText)) }
    var pinned: Bool { members.contains(where: \.pinned) }
    var playable: [PrivateArchive] { members.filter { !$0.deleted && !$0.audioDeleted && !$0.chunks.isEmpty } }

    func match(_ query: String) -> String? {
        let current = text
        if query.isEmpty || current.localizedCaseInsensitiveContains(query) { return current }
        return members.lazy.flatMap { $0.versions.reversed() }.first { $0.text.localizedCaseInsensitiveContains(query) }?.text
    }

    static func assemble(_ archives: [PrivateArchive]) -> [Self] {
        let groups = Dictionary(grouping: archives.filter { !$0.deleted }) { $0.paragraph?.id ?? $0.id }
        var natural: [ReaderParagraph] = []
        for (id, entries) in groups {
            let ordered = entries.sorted { $0.readingOrder < $1.readingOrder }
            guard let first = ordered.first else { continue }
            natural.append(Self(id: id, started: first.paragraph?.start ?? first.started, members: ordered))
        }
        natural.sort { $0.members[0].readingOrder < $1.members[0].readingOrder }
        var visible: [Self] = []
        for item in natural {
            let boundary = item.members.compactMap(\.paragraph).max {
                ($0.edited, $0.hidden ? 1 : 0) < ($1.edited, $1.hidden ? 1 : 0)
            }
            if !visible.isEmpty, boundary?.hidden == true {
                visible[visible.count - 1].members.append(contentsOf: item.members)
            } else { visible.append(item) }
        }
        return visible.reversed()
    }
}
