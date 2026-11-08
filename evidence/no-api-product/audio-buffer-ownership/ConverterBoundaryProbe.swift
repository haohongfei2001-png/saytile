import Foundation
@preconcurrency import AVFoundation
import CAudio
@testable import SaytileKit

struct Conversion: Codable { let chunk: Int; let primeMethod: String; let leading: UInt32; let trailing: UInt32; let inputFrames: Int; let normalFrames: Int; let tailFrames: Int; let callbackRequests: [UInt32]; let statuses: [String]; let outputPath: String }
@main struct ConverterBoundaryProbe {
 static func main() async throws {
  let args=CommandLine.arguments
  let file=try AVAudioFile(forReading:URL(fileURLWithPath:args[1]))
  let input=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:UInt32(file.length))!;try file.read(into:input)
  let source=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:input.format.sampleRate,channels:1,interleaved:false)!
  let target=AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:false)!
  let destination=URL(fileURLWithPath:args[2]);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
  let totalFrames=args.count>3 ? Int(Double(args[3])!*source.sampleRate) : Int(input.frameLength)
  var result:[Conversion]=[]
  for size in (args.count>3 ? [8192] : [1024,8192,-1,Int(input.frameLength)]) {
   for method in (args.count>3 ? [AVAudioConverterPrimeMethod.normal] : [.normal,.none,.pre]) {
    let converter=AVAudioConverter(from:source,to:target)!;converter.primeMethod=method
    var bytes=Data(),requests:[UInt32]=[],states:[String]=[],offset=0,normalFrames=0,tailFrames=0
    while offset<totalFrames {
     let selectedSize=size == -1 ? ([8192,1024,1024,512,1024][states.count % 5]) : size
     let count=min(selectedSize,totalFrames-offset)
     let buffer=AVAudioPCMBuffer(pcmFormat:source,frameCapacity:UInt32(count))!;buffer.frameLength=UInt32(count)
     var copied=0
     while copied<count { let index=(offset+copied)%Int(input.frameLength);let n=min(count-copied,Int(input.frameLength)-index);buffer.floatChannelData![0].advanced(by:copied).update(from:input.floatChannelData![0].advanced(by:index),count:n);copied+=n }
     let output=AVAudioPCMBuffer(pcmFormat:target,frameCapacity:UInt32(ceil(Double(count)*16000/source.sampleRate)+32))!
     var supplied=false,error:NSError?
     let status=converter.convert(to:output,error:&error) { needed,state in
      requests.append(needed)
      if supplied { state.pointee = .noDataNow;return nil };supplied=true;state.pointee = .haveData;return buffer
     }
     if status == .error { throw error! }
     bytes.append(Data(bytes:output.int16ChannelData![0],count:Int(output.frameLength)*2));normalFrames+=Int(output.frameLength);states.append("feed:\(status.rawValue):\(output.frameLength):supplied=\(supplied):source=\(count)");offset+=count
    }
    for _ in 0..<10 {
     let output=AVAudioPCMBuffer(pcmFormat:target,frameCapacity:4096)!;var error:NSError?
     let status=converter.convert(to:output,error:&error){needed,state in requests.append(needed);state.pointee = .endOfStream;return nil}
     if status == .error { throw error! }
     bytes.append(Data(bytes:output.int16ChannelData![0],count:Int(output.frameLength)*2));tailFrames+=Int(output.frameLength);states.append("tail:\(status.rawValue):\(output.frameLength)")
     if output.frameLength==0 || status == .endOfStream { break }
    }
    let path=destination.appendingPathComponent("converted-\(size)-\(method.rawValue).pcm");try bytes.write(to:path)
    result.append(Conversion(chunk:size,primeMethod:String(method.rawValue),leading:converter.primeInfo.leadingFrames,trailing:converter.primeInfo.trailingFrames,inputFrames:totalFrames,normalFrames:normalFrames,tailFrames:tailFrames,callbackRequests:requests,statuses:states,outputPath:path.path))
   }
  }
  print(String(decoding:try JSONEncoder().encode(result),as:UTF8.self))
  if args.count>3 { return }
  // Use the unmodified production run/stop/flushTail, feeding one bounded ring.
  let store=try SaytileStore(directory:destination.appendingPathComponent("worker-store"))
  let ring=try AudioRing(capacity:UInt32(input.frameLength)+1)
  let worker=try CaptureWorker(store:store,ring:ring,sampleRate:source.sampleRate,recognitionEnabled:false,update:{_,_ in},failed:{print("WORKER_FAILED \($0)")})
  var channel:UnsafeMutablePointer<Float>?=input.floatChannelData![0]
  withUnsafePointer(to:&channel){st_ring_write(ring.pointer,$0,1,input.frameLength)}
  await worker.start();await worker.stop()
  let rows=try await store.listRecordings(limit:100)
  print("PRODUCTION_WORKER frames=\(rows.reduce(0){$0+Int64(($1.duration*16000).rounded())}) recordings=\(rows.count) dropped=\(st_ring_dropped(ring.pointer))")
  try await store.close()
 }
}
