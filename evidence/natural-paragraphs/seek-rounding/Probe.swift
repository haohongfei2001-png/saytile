import AppKit
import AVFoundation
import Combine
import Foundation
@testable import SaytileKit

@main struct Probe {
 @MainActor static func main() async throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let base=URL(fileURLWithPath:"/private/tmp/saytile-playback-seek-repro/data-"+UUID().uuidString)
  let store=try SaytileStore(directory:base)
  func silent(_ counts:[Int]) async throws -> UUID {
   let r=try await store.createRecording()
   let journal=try PCMJournal(directory:store.audioDirectory,recordingID:r.id)
   for n in counts {
    try journal.openChunk();try journal.append(Data(repeating:0,count:n*2));try journal.closeChunk()
    try await store.registerAudioChunk(recordingID:r.id,relativePath:journal.relativePath,frames:Int64(n))
   }
   try await store.finishRecording(id:r.id)
   return r.id
  }
  let first=try await silent([6400,4800]),second=try await silent([14400])
  let deleted=try await silent([8000]),missing=try await silent([8000])
  try await store.deleteAudio(recordingID:deleted)
  let c=try await store.audioChunks(recordingID:missing)[0]
  try FileManager.default.removeItem(at:await store.audioURL(for:c))
  let controller=AudioController(store:store)
  let start=ProcessInfo.processInfo.systemUptime
  func rawPlayer()->AVAudioPlayer? {
   let v=Mirror(reflecting:controller).children.first { $0.label=="player" }?.value
   guard let v else{return nil}
   return Mirror(reflecting:v).children.first?.value as? AVAudioPlayer
  }
  func record(_ event:String,_ iteration:Int,_ observed:Double?=nil) {
   let d:[String:Any] = ["event":event,"iteration":iteration,"t":ProcessInfo.processInfo.systemUptime-start,
    "position":controller.playbackPosition,"publishedPosition":observed ?? controller.playbackPosition,
    "position_hex":String(controller.playbackPosition.bitPattern,radix:16),
    "playingID":controller.playingID==first ? "first":controller.playingID==nil ? "none":"other",
    "playingRecordingID":controller.playingRecordingID==first ? "first":controller.playingRecordingID==second ? "second":"none",
    "rawCurrentTime":rawPlayer()?.currentTime ?? -1,"rawDuration":rawPlayer()?.duration ?? -1]
   print(String(decoding:try! JSONSerialization.data(withJSONObject:d,options:[.sortedKeys]),as:UTF8.self))
  }
  var iter=0
  let observation=controller.$playbackPosition.sink { p in record("published",iter,p) }
  for (i,delay) in [0,85,95,100,0,90,0,95].enumerated() {
   iter=i
   try await controller.play(recordingIDs:[first,deleted,missing,second,first],playbackID:first)
   if delay>0 {try await Task.sleep(for:.milliseconds(delay))}
   record("before_seek",i)
   controller.seekPlayback(to:0.9)
   record("seek_sync",i)
   for n in 0..<30 {
    try await Task.sleep(for:.milliseconds(5))
    record("poll_\(n)",i)
   }
   controller.stopPlayback()
  }
  observation.cancel();await controller.shutdown();try await store.close()
 }
}
