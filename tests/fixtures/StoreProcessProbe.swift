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
        #if SAYTILE_PACKAGE_PROBE
        case "crash-live", "crash-first-flush", "crash-rotation":
            let failedFlush = mode == "crash-first-flush"
            var io = PCMJournal.IO.live
            if failedFlush {
                io.synchronize = { handle in
                    // Creation succeeds. The first attempt to flush actual
                    // samples and the close-time retry both hit a disk error.
                    if try handle.seekToEnd() > 44 { throw POSIXError(.ENOSPC) }
                    try handle.synchronize()
                }
            }
            let worker = try CaptureWorker(store: store, ring: AudioRing(capacity: 32_000),
                sampleRate: 16_000, recognitionEnabled: false, journalIO: io,
                update: { _, _ in }, failed: { _ in })
            try await worker.beginUtterance()
            guard let id = await worker.recordingID else { throw ProbeFailure.failed("no active capture") }
            // Pass production-sized PCM frames through the journal/rotation path.
            let bodyFrames = failedFlush ? 0 : 15 * 16_000
            let totalFrames = bodyFrames + (mode == "crash-rotation" ? 0 : 4000)
            let expected = syntheticPCM(frames: totalFrames)
            for offset in stride(from: 0, to: expected.count, by: 640) {
                try await worker.append(expected.subdata(in: offset..<min(offset + 640, expected.count)))
            }
            let ticket = try await store.beginRecognition(recordingID: id)
            let ingress = LocalCandidateIngress(store: store, ticket: ticket)
            try await ingress.receive(.init(text: "离线实时草稿", stableUTF16Length: 0,
                                           audioEndSeconds: 0.25, isComplete: false))
            try check(try await store.timelinePage().entries.first?.recording.text == "离线实时草稿",
                      "real candidate publisher stores timeline text before SIGKILL")
            if failedFlush {
                do {
                    try await worker.endUtterance()
                    throw ProbeFailure.failed("injected media failure must stop capture")
                } catch let error as POSIXError where error.code == .ENOSPC {}
                try check(try await store.recording(id: id)?.audioState == .missing, "unconfirmed audio never advertised as saved")
            }
            try receipt(root, ["record": id.uuidString, "frames": String(totalFrames)])
            try await park()
        case "verify-live", "verify-live-again":
            let saved = try readReceipt(root)
            guard let id = saved["record"].flatMap(UUID.init(uuidString:)),
                  let frames = saved["frames"].flatMap(Int.init) else { throw ProbeFailure.failed("fixture receipt") }
            let repairs = try await AudioDiagnostics.recoverAudio(store: store)
            let expectedRepairs = mode == "verify-live" && frames != 240000 ? 1 : 0
            try check(repairs == expectedRepairs, "startup tail repair is idempotent")
            let rows = try await store.timelinePage().entries
            try check(rows.count == 1 && rows[0].id == id && rows[0].recording.text == "离线实时草稿",
                      "one original timeline row retains its displayed partial")
            try check(rows[0].recording.audioState == .available && !rows[0].recording.isRecording,
                      "interrupted WAV available after reopening")
            let chunks = try await store.audioChunks(recordingID: id)
            let expectedChunks: [Int64] = frames == 4000 ? [4000] : [240000, Int64(frames - 240000)]
            try check(chunks.map(\.frames) == expectedChunks,
                      "recovered sample counts include pre-checkpoint tail")
            var pcm = Data()
            for chunk in chunks where chunk.frames > 0 {
                let wav = try Data(contentsOf: await store.audioURL(for: chunk))
                try check(wav.prefix(44) == PCMJournal.header(frames: chunk.frames), "WAV header")
                pcm.append(wav.dropFirst(44))
            }
            try check(pcm == syntheticPCM(frames: frames), "all original PCM bytes match")
            try check(try await store.recognitionCandidates(recordingID: id).count == 1, "one local candidate, no replay")
            try check(try await store.latestDispatchableRevision(recordingID: id) == nil, "partial was never promoted for external delivery")
            try check(try await store.db.rows("PRAGMA fullfsync").first?["fullfsync"] == "1", "SQLite uses media flushes")
            try check(try await store.db.rows("PRAGMA quick_check").first?["quick_check"] == "ok", "SQLite integrity")
        #endif
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
            try check(try db.rows("PRAGMA user_version").first?["user_version"] == "6","schema upgrade committed")
            try check(try db.rows("SELECT COUNT(*) AS n FROM recording_cloud_authorizations").first?["n"] == "0",
                      "local and legacy recordings have no implicit cloud upload grants")
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
    #if SAYTILE_PACKAGE_PROBE
    static func syntheticPCM(frames: Int) -> Data {
        // Deterministic per-frame signal catches reorder, duplicate and substitution.
        Data((0..<(frames * 2)).map { i in UInt8(truncatingIfNeeded: (i &* 127) ^ (i >> 11)) })
    }
    #endif
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
