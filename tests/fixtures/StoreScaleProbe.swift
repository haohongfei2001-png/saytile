import Foundation
import Darwin
@testable import SaytileKit

@main struct StoreScaleProbe {
    static func main() async { do {try await run()} catch {print("SCALE_ERROR \(error)");exit(1)} }
    static func run() async throws {
        guard CommandLine.arguments.count == 3, let count = Int(CommandLine.arguments[2]), count >= 1_000 else {
            throw StoreError.database("Usage: isolated-directory count (at least 1000)")
        }
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        let store = try SaytileStore(directory:root)
        let seed = try StoreDatabase(url:root.appendingPathComponent("Saytile.sqlite"))
        try seed.configureForWriting()
        let schema = Int(try seed.rows("PRAGMA user_version").first?["user_version"] ?? "0") ?? 0
        guard schema == 6 else { throw StoreError.database("Scale probe requires current schema 6") }
        let begin = Date()
        FileHandle.standardError.write(Data("PHASE seed\n".utf8))
        try seed.transaction {
            try seed.execute("""
            WITH RECURSIVE sequence(n) AS(SELECT 1 UNION ALL SELECT n+1 FROM sequence WHERE n<?)
            INSERT INTO recordings(id,created_at,sample_rate,preferred_revision,is_recording,recognition_state,pinned)
            SELECT upper(printf('%08x-0000-4000-8000-%012x',n,n)),n,16000,upper(printf('%08x-1111-4111-8111-%012x',n,n)),0,CASE WHEN n%1000=0 THEN 'failed' ELSE 'completed' END,n%2 FROM sequence
            """,[.int(Int64(count))])
            for revision in 1...3 {
                try seed.execute("""
                INSERT INTO revisions(id,recording_id,text,origin,created_at,base_revision)
                SELECT upper(printf('%08x-\(revision)\(revision)\(revision)\(revision)-4\(revision)\(revision)\(revision)-8\(revision)\(revision)\(revision)-%012x',created_at,created_at)),id,
                '长期语音档案第'||created_at||'条。今天讨论产品设计、中文识别和可靠存储，文字版本应始终可检索。'||CASE WHEN created_at%1000=0 THEN '验收关键词' ELSE '' END,
                CASE WHEN \(revision)=1 THEN 'final' ELSE 'userEdit' END,created_at,NULL FROM recordings
                """)
            }
        }
        FileHandle.standardError.write(Data("PHASE partial writes\n".utf8))
        let seedSeconds = Date().timeIntervalSince(begin)
        try seed.close()
        let live = try await store.createRecording(), ticket = try await store.beginRecognition(recordingID:live.id)
        var samples:[Double]=[]
        for index in 0..<200 {
            let start = Date()
            try await store.applyRecognition(ticket:ticket,text:"连续表达第\(index)个部分结果",isFinal:false)
            samples.append(Date().timeIntervalSince(start)*1000)
        }
        samples.sort()
        FileHandle.standardError.write(Data("PHASE queries\n".utf8))
        let searchStart = Date(), matches = try await store.listRecordings(query:"验收关键词",limit:200)
        let searchMS = Date().timeIntervalSince(searchStart)*1000
        let pageStart = Date(), page = try await store.listRecordings(limit:100,offset:count-100)
        let pageMS = Date().timeIntervalSince(pageStart)*1000
        let recoveryStart = Date(), pending = try await store.claimRecoveryRecording()
        let recoveryMS = Date().timeIntervalSince(recoveryStart)*1000
        let cleanupIDs = try await store.listRecordings(limit:1000,offset:1000).map(\.id)
        let cleanupTask = Task { try await store.cleanupAudio(recordingIDs:cleanupIDs,olderThan:Date()) }
        var responsive:[Double]=[]
        for index in 0..<100 {
            let start = Date()
            try await store.saveDraft(recordingID:live.id,text:"清理期间仍可写入第\(index)次")
            responsive.append(Date().timeIntervalSince(start)*1000)
            await Task.yield()
        }
        let deleted = try await cleanupTask.value
        responsive.sort()
        let stats:[String:Any] = ["schema":schema,"recordings":count,"revisions":count*3,"seed_seconds":seedSeconds,"partial_writes":samples.count,"partial_write_p50_ms":samples[samples.count/2],"partial_write_p95_ms":samples[Int(Double(samples.count)*0.95)],"partial_write_max_ms":samples.last!,"search_ms":searchMS,"search_matches":matches.count,"last_page_ms":pageMS,"last_page_count":page.count,"recovery_claim_ms":recoveryMS,"recovery_found":pending != nil,"cleanup_count":deleted,"concurrent_write_p95_ms":responsive[95],"concurrent_write_max_ms":responsive.last!,"scope":"Synthetic metadata archive with actual Store queries and SQLite FULL writes; cleanup tests metadata scheduling only, excludes audio files and UI"]
        print(String(data:try JSONSerialization.data(withJSONObject:stats,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
        guard matches.count == count/1000,page.count == 100,pending != nil,samples.last! < 1000 else { throw StoreError.database("规模验证不满足基本响应要求") }
        try await store.close()
    }
}
