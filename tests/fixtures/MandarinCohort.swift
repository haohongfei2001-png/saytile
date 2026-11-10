import Foundation
import AVFoundation
import CryptoKit
@testable import SaytileKit

// Quality-only fast replay: timing comes exclusively from separate wall-paced AppKit observations.
@main struct MandarinCohort {
 struct Row:Decodable {let id:String; let audio_sha256:String}
 static func main() async throws {
    let a=CommandLine.arguments
    guard a.count==8, let m=LocalASRID(rawValue:a[1]), ["product","direct"].contains(a[2]) else {exit(64)}
    let wav=URL(fileURLWithPath:a[4]), weights=URL(fileURLWithPath:a[5]), helpers=URL(fileURLWithPath:a[6])
    let list=try JSONDecoder().decode([Row].self,from:Data(contentsOf:URL(fileURLWithPath:a[3])))
    let out=URL(fileURLWithPath:a[7]);guard !FileManager.default.fileExists(atPath:out.path) else {exit(65)}
    FileManager.default.createFile(atPath:out.path,contents:nil);let log=try FileHandle(forWritingTo:out)
    if m == .apple { try await AppleSpeechService.prepare() }
    let svc=LocalASRService(root:weights, helpers:helpers)
    let factory=RecognitionSessionFactory()
    factory.selectLocal(live:m,archive:m,service:svc)
    for row in list {
      let file=wav.appending(path:row.id+".wav")
      guard SHA256.hash(data:try Data(contentsOf:file)).map({String(format:"%02x",$0)}).joined()==row.audio_sha256 else {exit(66)}
      let tmp=FileManager.default.temporaryDirectory.appending(path:"saytile-mandarin-"+UUID().uuidString)
      defer { try? FileManager.default.removeItem(at:tmp) }
      let store=try SaytileStore(directory:tmp)
      let reader=try AVAudioFile(forReading:file,commonFormat:.pcmFormatFloat32,interleaved:false)
      guard let buf=AVAudioPCMBuffer(pcmFormat:reader.processingFormat,frameCapacity:AVAudioFrameCount(reader.length)) else {exit(67)}
      try reader.read(into:buf)
      let w=try CaptureWorker(store:store,ring:AudioRing(capacity:64000),sampleRate:16000,recognitionFactory:factory,update:{_,_ in},failed:{_ in})
      var session:(any RecognitionSession)?
      if a[2]=="direct" {
        let rec=try await store.createRecording();let ticket=try await store.beginRecognition(recordingID:rec.id)
        session=factory.make(store:store,ticket:ticket,newCapture:true)
      }
      let n=Int(buf.frameLength),start=Date()
      for i in stride(from:0,to:n,by:3200){
        let count=min(3200,n-i)
        let part=Array(UnsafeBufferPointer(start:buf.floatChannelData![0]+i,count:count))
        for data in try await w.convertCapturedSamples(part,count:UInt32(count)) {
          if let session {session.append(data)} else {try await w.acceptPCM(data,endingAt:start.addingTimeInterval(Double(i+count)/16000))}
        }
        try await Task.sleep(for:.milliseconds(3))
      }
      if let session {session.finish(); await session.wait()} else {
        await w.stop()
        let deadline=ContinuousClock.now + .seconds(150)
        while await w.hasPendingRecognition() {if ContinuousClock.now>deadline {throw CocoaError(.fileReadUnknown)};try await Task.sleep(for:.milliseconds(12))}
      }
      let recs=try await store.listRecordings(limit:100)
      var providers=Set<String>()
      for r in recs {providers.formUnion(try await store.modelRuns(recordingID:r.id).map{$0.ticket.provider})}
      guard providers.isSubset(of:[m == .apple ? "apple-speech-analyzer" : m.rawValue]) else {exit(68)}
      let d:[String:Any]=["id":row.id,"model":m.rawValue,"path":a[2],"text":recs.reversed().map(\.text).joined(),"states":recs.reversed().map{$0.recognitionState.rawValue},"errors":recs.compactMap(\.lastError),"providers":providers.sorted()]
      try log.write(contentsOf:JSONSerialization.data(withJSONObject:d,options:[.sortedKeys])+Data([10]))
    }
    await svc.releaseIdle()
 }
}
