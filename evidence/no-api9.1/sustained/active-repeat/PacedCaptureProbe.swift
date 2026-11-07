import Foundation
import AVFoundation
import CAudio
@testable import SaytileKit

struct ProbeFailure: Error, CustomStringConvertible { var description: String }
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    return try encoder.encode(value)
}
struct AudioInput {
    var samples: [Float]
    var rate: Double
    init(url: URL) throws {
        let file = try AVAudioFile(forReading:url, commonFormat:.pcmFormatFloat32, interleaved:false)
        let format = file.processingFormat
        guard format.channelCount == 1, file.length > 0, file.length < 1_000_000,
              let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(file.length)) else {
            throw ProbeFailure(description:"expected a bounded mono synthetic AIFF")
        }
        try file.read(into:buffer)
        guard let source = buffer.floatChannelData?[0], buffer.frameLength == file.length else {
            throw ProbeFailure(description:"incomplete synthetic AIFF read")
        }
        samples=Array(UnsafeBufferPointer(start:source,count:Int(buffer.frameLength)))
        rate=format.sampleRate
    }
}
struct Transition: Codable { let elapsed:Double; let speaking:Bool; let level:Float }
final class CaptureTrace: @unchecked Sendable {
    let start:Double
    private let lock=NSLock()
    private var states:[Transition]=[]
    private var failures:[String]=[]
    init(start:Double) { self.start=start }
    func update(_ speaking:Bool, _ level:Float) {
        lock.withLock {
            guard states.last?.speaking != speaking else { return }
            states.append(.init(elapsed:now()-start,speaking:speaking,level:level))
        }
    }
    func fail(_ message:String) { lock.withLock { failures.append(message) } }
    func result() -> ([Transition],[String]) { lock.withLock { (states,failures) } }
}
struct Observation: Codable, Equatable {
    let id:UUID;let state:String;let open:Bool;let text:String
    init(_ row:Recording) { id=row.id;state=row.recognitionState.rawValue;open=row.isRecording;text=row.text }
}
struct Sample: Codable { let elapsed:Double;let row:Observation }
struct Chunk: Codable { let path:String;let frames:Int64;let bytes:Int;let valid:Bool }
struct RecordReport: Codable {
    let row:Observation;let lastError:String?;let chunks:[Chunk];let revisionOrigins:[String]
    let candidates:[RecognitionCandidate];let finalRevision:String?
}
struct Report: Codable {
    let sampleRate:Double;let totalInputFrames:Int;let schedule:[String:Double];let feedActualSeconds:Double
    let initialAssetStatus:String;let prepareCalls:Int;let finalAssetStatus:String;let usesCloud:Bool
    let microphoneOpened:Bool;let transitions:[Transition];let workerErrors:[String]
    let ringDropped:UInt64;let observations:[Sample];let records:[RecordReport]
}
@main struct LocalVADAppleProbe {
    static func main() async {
        do { try await run() }
        catch { print("LOCAL_VAD_APPLE_ERROR \(error)");exit(1) }
    }
    static func run() async throws {
        let args=CommandLine.arguments
        guard args.count==5 else { throw ProbeFailure(description:"usage: input1.aiff input2.aiff new-store report.json") }
        let first=try AudioInput(url:URL(fileURLWithPath:args[1]))
        let second=try AudioInput(url:URL(fileURLWithPath:args[2]))
        guard first.rate==second.rate && first.rate>=16_000 else { throw ProbeFailure(description:"unexpected rate") }
        let directory=URL(fileURLWithPath:args[3],isDirectory:true)
        guard !FileManager.default.fileExists(atPath:directory.path) else { throw ProbeFailure(description:"store must be new") }
        let store=try SaytileStore(directory:directory)
        let ring=try AudioRing(capacity:131_072)
        let initial=await AppleSpeechService.availability()
        var prepared=0
        // Same public on-device language setup as Saytile Settings. This does not open an audio device.
        if initial.supported && !initial.installed {
            prepared=1
            print("APPLE_ASSET_PREPARE current=\(initial.message)")
            try await AppleSpeechService.prepare()
        }
        let ready=await AppleSpeechService.availability()
        print("APPLE_ASSET supported=\(ready.supported) installed=\(ready.installed) preparations=\(prepared)")
        guard ready.installed else { throw ProbeFailure(description:ready.message) }
        let lead=Int(first.rate*0.25),pause=Int(first.rate*1.6),tail=Int(first.rate*1.6)
        var signal=[Float](repeating:0,count:lead)
        signal.append(contentsOf:first.samples);signal.append(contentsOf:[Float](repeating:0,count:pause))
        signal.append(contentsOf:second.samples);signal.append(contentsOf:[Float](repeating:0,count:tail))
        let schedule=["cycleSeconds":180.0, "cycleCount":40.0, "firstStart":Double(lead)/first.rate,"firstEnd":Double(lead+first.samples.count)/first.rate,
                      "secondStart":Double(lead+first.samples.count+pause)/first.rate,"secondEnd":Double(signal.count-tail)/first.rate,
                      "total":Double(signal.count)/first.rate]
        let t0=now();let trace=CaptureTrace(start:t0)
        // No recognitionFactory argument: this selects the real default production factory, local SpeechAnalyzer.
        let worker=try CaptureWorker(store:store,ring:ring,sampleRate:first.rate,
                     update:{ trace.update($0,$1) },failed:{ trace.fail($0) })
        let cloud=await worker.recognitionFactory.usesCloud
        guard !cloud else { throw ProbeFailure(description:"default unexpectedly selected cloud") }
        var previous:[UUID:Observation]=[:],polls:[Sample]=[]
        func poll() async throws {
            let rows=try await store.listRecordings(limit:200)
            for row in rows.reversed() {
                let obs=Observation(row)
                if previous[row.id] != obs {
                    previous[row.id]=obs;polls.append(.init(elapsed:now()-t0,row:obs))
                    print("ROW \(String(format:"%.3f",now()-t0)) \(row.id) \(obs.state) open=\(obs.open) text=\(obs.text)")
                }
            }
        }
        await worker.start()
        let step=max(1,Int(first.rate*0.02))
        let period = Int(first.rate) * 180
        let total = period * 40
        signal.append(contentsOf: repeatElement(Float.zero, count: period - signal.count))
        for i in stride(from:0,to:total,by:step) {
            let deadline=t0+Double(i)/first.rate-now()
            if deadline>0 {try await Task.sleep(for:.seconds(deadline))}
            let count=min(step,total-i)
            signal.withUnsafeMutableBufferPointer { all in
                var channel=all.baseAddress?.advanced(by:i % period)
                withUnsafePointer(to:&channel) { st_ring_write(ring.pointer,$0,1,UInt32(count)) }
            }
            if (i/step).isMultiple(of:50) { try await poll() }
        }
        let feedSeconds=now()-t0
        await worker.stop()
        let cutoff=now()+22
        repeat {
            try await poll()
            let rows=try await store.listRecordings(limit:200)
            if !rows.isEmpty && rows.allSatisfy({ !$0.isRecording && [.completed,.failed,.cancelled].contains($0.recognitionState) }) { break }
            try await Task.sleep(for:.milliseconds(100))
        } while now()<cutoff
        var results:[RecordReport]=[]
        for row in (try await store.listRecordings(limit:200)).reversed() {
            var chunks:[Chunk]=[]
            for c in try await store.audioChunks(recordingID:row.id) {
                let url=try await store.audioURL(for:c)
                let data=try Data(contentsOf:url)
                chunks.append(.init(path:c.relativePath,frames:c.frames,bytes:data.count,
                         valid:data.starts(with:Data("RIFF".utf8)) && data.count==44+2*Int(c.frames) && c.frames>0))
            }
            results.append(.init(row:Observation(row),lastError:row.lastError,chunks:chunks,
                     revisionOrigins:try await store.revisions(recordingID:row.id).map(\.origin.rawValue),
                     candidates:try await store.recognitionCandidates(recordingID:row.id),
                     finalRevision:try await store.latestFinalRevision(recordingID:row.id)?.text))
        }
        let (transitions,failures)=trace.result()
        let report=Report(sampleRate:first.rate,totalInputFrames:total,schedule:schedule,feedActualSeconds:feedSeconds,
              initialAssetStatus:initial.message,prepareCalls:prepared,finalAssetStatus:ready.message,usesCloud:cloud,microphoneOpened:false,
              transitions:transitions,workerErrors:failures,ringDropped:UInt64(st_ring_dropped(ring.pointer)),observations:polls,records:results)
        try encoded(report).write(to:URL(fileURLWithPath:args[4]),options:.atomic)
        print("LOCAL_VAD_APPLE_OBSERVED rows=\(results.count) transitions=\(transitions.count) drops=\(report.ringDropped) capture_errors=\(failures.count)")
        await worker.cancelRecognitionAndWait()
        try await store.close()
    }
}
