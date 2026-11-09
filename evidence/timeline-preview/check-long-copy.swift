// Link the production SaytileKit from the preview source. All rows are synthetic.
import Foundation
import SaytileKit

@main struct LongGroupCopy {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-long-group-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SaytileStore(directory: root)
        let t = Calendar.current.startOfDay(for: .now).addingTimeInterval(36_000)
        var words: [String] = []
        for n in 0..<145 {
            let time = t.addingTimeInterval(Double(n))
            let row = try await store.createRecording(createdAt: time)
            words.append("合成原话 \(n)，嗯，再说一次😀。")
            try await store.saveEdit(recordingID: row.id, text: words[n])
            try await store.finishRecording(id: row.id, speechEndedAt: time)
        }
        let pending = try await store.createRecording(createdAt: t.addingTimeInterval(145))
        let drawn = try await store.timelinePage().entries
        let tail = drawn.last!
        guard drawn.count == 64 && tail.id == pending.id && tail.recording.text.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let displayed = Dictionary(uniqueKeysWithValues: drawn.map { ($0.position, $0.recording.text) })
        let ticket = try await store.beginRecognition(recordingID: pending.id)
        try await store.applyRecognition(ticket: ticket, text: "点击前刚到但尚未显示的回调", isFinal: false)
        let click = try store.timelineCopy(group: tail.group, through: tail.position, displayed: displayed)
        let next = try await store.createRecording(createdAt: t.addingTimeInterval(500))
        try await store.saveEdit(recordingID: next.id, text: "下一个时间组")
        let nextTail = try await store.timelinePage().entries.last!
        guard click.utf8.elementsEqual(words.joined(separator: "\n").utf8),
              nextTail.group != tail.group,
              try store.timelineCopy(group: nextTail.group, through: nextTail.position, displayed: [:]) == "下一个时间组" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try await store.close()
        print("PASS group=146 current_window=64 copied_nonempty=145 empty_at_paint=preserved next_group=isolated")
    }
}
