import AppKit
import CSQLite
import RiftletFeedback

/// Compiles the actual settings controller. No window, Keychain, network, microphone or archive access.
private actor PendingFeedbackTransport: FeedbackTransport {
    nonisolated let configured = true
    private(set) var calls = 0
    private var pending: CheckedContinuation<Void, Never>?
    func perform(_ action: FeedbackRequest, record: FeedbackRecord, secret: String) async throws -> FeedbackReceipt {
        calls += 1
        await withCheckedContinuation { pending = $0 }
        return FeedbackReceipt(id: record.id)
    }
    func release() { pending?.resume(); pending = nil }
}

@main struct FeedbackSettingsModelProbe {
    struct Failure: Error { let message: String }
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-feedback-host-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0
        func require(_ value: Bool, _ label: String) throws {
            guard value else { throw Failure(message: label) }
            checks += 1; print("PASS " + label)
        }
        func waitReady(_ model: FeedbackSettingsModel) async throws {
            for _ in 0..<500 {
                if model.ready { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw Failure(message: "controller ready timed out")
        }
        func database(_ home: URL, sql: String) throws -> String? {
            var db: OpaquePointer?
            let path = home.appendingPathComponent("Feedback-v01/feedback.sqlite").path
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { throw Failure(message: "open fixture database") }
            defer { sqlite3_close(db) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw Failure(message: "prepare fixture SQL") }
            defer { sqlite3_finalize(statement) }
            let code = sqlite3_step(statement)
            guard code == SQLITE_ROW || code == SQLITE_DONE else { throw Failure(message: "execute fixture SQL") }
            return code == SQLITE_ROW ? String(cString: sqlite3_column_text(statement, 0)) : nil
        }
        func storedDraft(_ home: URL) throws -> FeedbackDraft {
            let text = try database(home, sql: "SELECT payload FROM draft WHERE id=1") ?? ""
            return try JSONDecoder().decode(FeedbackDraft.self, from: Data(text.utf8))
        }
        do {
            let home = root.appendingPathComponent("rapid-edit")
            let model = FeedbackSettingsModel(directory: home, normalLaunch: false)
            try await waitReady(model)
            for index in 1...40 { model.edit(text: "仅合成反馈 \(index)") }
            await model.prepareForExit()
            try require(!model.hasUnsavedDraft && model.closing && (try storedDraft(home).text) == "仅合成反馈 40", "rapid edits then immediate exit preserve latest draft")
            model.edit(text: "must not replace while closing"); model.send()
            try require(model.draft.text == "仅合成反馈 40" && !model.canSend, "closing prevents new edits and send")
            model.cancelExit(); model.edit(text: "取消退出后仍可编辑")
            await model.prepareForExit()
            try require(try storedDraft(home).text == "取消退出后仍可编辑", "cancelled exit reopens editing and preserves the next draft")
            await model.finishExit()
        }
        do {
            let home = root.appendingPathComponent("save-failure")
            let model = FeedbackSettingsModel(directory: home, normalLaunch: false)
            try await waitReady(model)
            _ = try database(home, sql: "CREATE TRIGGER reject_draft BEFORE UPDATE ON draft BEGIN SELECT RAISE(ABORT,'fixture'); END")
            model.edit(text: "保存失败也不能丢失")
            await model.prepareForExit()
            try require(model.hasUnsavedDraft && model.draft.text == "保存失败也不能丢失", "SQLite draft failure retains unsaved text and blocks clean exit")
            model.cancelExit()
            _ = try database(home, sql: "DROP TRIGGER reject_draft")
            await model.prepareForExit()
            try require(!model.hasUnsavedDraft && (try storedDraft(home).text) == "保存失败也不能丢失", "retry after storage recovery saves the original draft")
            await model.finishExit()
        }
        do {
            let home = root.appendingPathComponent("send-exit")
            let model = FeedbackSettingsModel(directory: home, normalLaunch: false)
            try await waitReady(model)
            model.edit(text: "发送后立即退出"); model.send()
            await model.prepareForExit()
            await model.reload()
            try require(model.records.count == 1 && model.records.first?.envelope.product == .saytile && model.records.first?.envelope.text == "发送后立即退出", "send then immediate exit commits exactly one Saytile report")
            try require(model.records.first?.attempts == 0 && !model.hasUnsavedDraft && (try storedDraft(home).text).isEmpty, "disabled transport stays offline and committed send clears only its draft")
            await model.finishExit()
        }
        do {
            let home = root.appendingPathComponent("enqueue-failure")
            let model = FeedbackSettingsModel(directory: home, normalLaunch: false)
            try await waitReady(model)
            _ = try database(home, sql: "CREATE TRIGGER reject_report BEFORE INSERT ON reports BEGIN SELECT RAISE(ABORT,'fixture'); END")
            model.edit(text: "提交失败仍有已保存草稿"); model.send()
            await model.prepareForExit(); await model.reload()
            try require(model.records.isEmpty && model.draft.text == "提交失败仍有已保存草稿" && (try storedDraft(home).text) == model.draft.text, "enqueue failure leaves persisted draft and creates no report")
            model.cancelExit()
            _ = try database(home, sql: "DROP TRIGGER reject_report")
            model.send(); await model.prepareForExit(); await model.reload()
            try require(model.records.count == 1 && model.draft.text.isEmpty, "explicit retry after enqueue failure commits one report")
            await model.finishExit()
        }
        do {
            let home = root.appendingPathComponent("pending-network")
            let transport = PendingFeedbackTransport()
            let model = FeedbackSettingsModel(directory: home, normalLaunch: false, transport: transport)
            try await waitReady(model)
            model.edit(text: "慢网络不能阻止安全退出"); model.send()
            for _ in 0..<500 {
                if await transport.calls == 1 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            try require(await transport.calls == 1, "controlled pending transport receives explicit submission only")
            let start = ContinuousClock.now
            await model.prepareForExit(); await model.finishExit()
            try require(start.duration(to: .now) < .seconds(1), "exit waits for local durability but not the pending network response")
            try require(try database(home, sql: "SELECT count(*) FROM reports") == "1", "pending network exit retains one durable report")
            await transport.release()
        }
        print("FeedbackSettingsModelProbe: \(checks)/\(checks) PASS")
    }
}
