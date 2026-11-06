import Foundation
import Darwin
#if SAYTILE_PACKAGE_PROBE
@testable import SaytileKit
#endif

@main struct StoreProcessProbe {
    static func main() async {
        do { try await run() }
        catch { print("PROBE_ERROR: \(error.localizedDescription)"); exit(1) }
    }
    static func run() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else { fatalError("mode directory") }
        let mode = arguments[1], root = URL(fileURLWithPath:arguments[2])
        let store = try SaytileStore(directory:root)
        switch mode {
        case "seed-beta", "crash-seed":
            let binding = try await store.createBinding(label:"独立测试目标")
            let record = try await store.createRecording()
            let file = store.audioDirectory.appendingPathComponent(record.id.uuidString + "/fixture.wav")
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data(repeating:0,count:32044).write(to:file)
            let handle = try FileHandle(forUpdating:file); try handle.synchronize(); try handle.close()
            try await store.registerAudioChunk(recordingID:record.id,relativePath:record.id.uuidString + "/fixture.wav",frames:16000)
            let ticket = try await store.beginRecognition(recordingID:record.id)
            try await store.applyRecognition(ticket:ticket,text:"升级原始文字",isFinal:true)
            let revision = try await store.saveEdit(recordingID:record.id,text:"升级修改稿")
            try await store.saveDraft(recordingID:record.id,text:"独立草稿待继续")
            try await store.setPinned(recordingID:record.id,pinned:true)
            let dispatch = try await store.reserveDispatch(bindingID:binding,recordingID:record.id,revisionID:revision.id,stableUTF16End:revision.text.utf16.count)!
            try receipt(root,["record":record.id.uuidString,"revision":revision.id.uuidString,"dispatch":dispatch.id.uuidString,"binding":binding.uuidString])
            if mode == "crash-seed" { try await park() }
        case "crash-delete":
            let saved = try readReceipt(root), id = UUID(uuidString:saved["record"]!)!
            _ = try await store.acquireAudioLease(recordingID:id)
            try await store.deleteAudio(recordingID:id)
            try Data("ready".utf8).write(to:root.appendingPathComponent("delete-ready"))
            try await park()
        case "crash-transaction":
            let saved = try readReceipt(root), id = saved["record"]!
            let transaction = try StoreDatabase(url:root.appendingPathComponent("Saytile.sqlite"))
            try transaction.execute("BEGIN IMMEDIATE")
            try transaction.execute("UPDATE editing_drafts SET text='未提交的错误覆盖' WHERE recording_id=?",[.text(id)])
            try Data("ready".utf8).write(to:root.appendingPathComponent("transaction-ready"))
            try await park()
        case "verify":
            let saved = try readReceipt(root), id = UUID(uuidString:saved["record"]!)!
            let record = try await store.recording(id:id)!
            try check(!record.isRecording,"interrupted capture closed")
            try check(record.recognitionState == .queued,"interrupted recognition queued")
            try check(record.text == "升级修改稿","selected edited version retained")
            try check(record.isPinned,"pin retained")
            try check(record.duration == 1,"durable audio coverage retained")
            try check(try await store.revisions(recordingID:id).count == 2,"all immutable versions retained")
            try check(try await store.loadDraft(recordingID:id) == "独立草稿待继续","draft retained")
            try check(try await store.dispatchState(id:UUID(uuidString:saved["dispatch"]!)!) == .unverified,"uncertain delivery not replayed")
            do {
                _ = try await store.reserveDispatch(bindingID:UUID(uuidString:saved["binding"]!)!,recordingID:id,revisionID:UUID(uuidString:saved["revision"]!)!,stableUTF16End:5)
                throw ProbeFailure.failed("binding should be invalid")
            } catch StoreError.bindingInvalid { print("PASS old binding invalid") }
            let db = try StoreDatabase(url:root.appendingPathComponent("Saytile.sqlite"))
            try check(try db.rows("PRAGMA quick_check").first?["quick_check"] == "ok","SQLite integrity")
            try check(try db.rows("PRAGMA user_version").first?["user_version"] == "3","schema upgrade committed")
        case "verify-delete":
            try await store.recoverPendingDeletions()
            let saved = try readReceipt(root),id = UUID(uuidString:saved["record"]!)!
            let record = try await store.recording(id:id)!
            try check(record.audioState == .deleted,"deletion intent resumed after SIGKILL")
            try check(record.text == "升级修改稿","audio erasure retains selected text")
            try check(try await store.revisions(recordingID:id).count == 2,"audio erasure retains all revisions")
            try check(try await store.loadDraft(recordingID:id) == "独立草稿待继续","audio erasure retains draft")
            try check(!FileManager.default.fileExists(atPath:store.audioDirectory.appendingPathComponent(id.uuidString).path),"physical owned audio removed")
        case "disk-fault":
            let record = try await store.createRecording()
            try await store.saveEdit(recordingID:record.id,text:"写入故障前的已保存文字")
            var original = rlimit()
            guard getrlimit(RLIMIT_FSIZE,&original) == 0 else { throw ProbeFailure.failed("getrlimit") }
            var restricted = original; restricted.rlim_cur = 131_072
            signal(SIGXFSZ,SIG_IGN)
            guard setrlimit(RLIMIT_FSIZE,&restricted) == 0 else { throw ProbeFailure.failed("setrlimit") }
            var failed = false
            do { try await store.saveEdit(recordingID:record.id,text:String(repeating:"大",count:400_000)) }
            catch { failed = true }
            _ = setrlimit(RLIMIT_FSIZE,&original)
            try check(failed,"real kernel file-size limit rejects oversized SQLite write")
            try check(try await store.recording(id:record.id)?.text == "写入故障前的已保存文字","failed transaction preserves selected text")
            try check(try await store.revisions(recordingID:record.id).count == 1,"failed transaction leaves no partial revision")
            try await store.saveDraft(recordingID:record.id,text:"空间恢复后可以继续")
            try check(try await store.loadDraft(recordingID:record.id) == "空间恢复后可以继续","writes resume after limit is restored")
        case "open": print("OPENED")
        default: fatalError("unknown probe mode")
        }
    }
    static func park() async throws { while true { try await Task.sleep(for:.seconds(60)) } }
    static func receipt(_ root:URL,_ value:[String:String]) throws {
        let url = root.appendingPathComponent("receipt.json")
        try JSONSerialization.data(withJSONObject:value,options:.sortedKeys).write(to:url)
        let file = try FileHandle(forUpdating:url);try file.synchronize();try file.close()
    }
    static func readReceipt(_ root:URL) throws -> [String:String] { try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("receipt.json"))) as! [String:String] }
    static func check(_ condition:Bool,_ message:String) throws { guard condition else { throw ProbeFailure.failed(message) }; print("PASS \(message)") }
    enum ProbeFailure:Error { case failed(String) }
}
