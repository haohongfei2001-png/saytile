import Foundation
import SaytileKit

@main struct Probe {
 static func main() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saytile-fusion-independent-" + UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try SaytileStore(directory: directory)
  let binding = try await store.createBinding(label: "synthetic-only")
  let record = try await store.createRecording()
  let path = record.id.uuidString + "/chunk.wav"
  let file = store.audioDirectory.appendingPathComponent(path)
  try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data(repeating: 0, count: 32044).write(to: file)
  try await store.registerAudioChunk(recordingID: record.id, relativePath: path, frames: 16000)
  try await store.finishRecording(id: record.id)
  let ticket = try await store.beginFusionRecognition(recordingID: record.id)
  let zh = ModelConfiguration(purpose: .chineseASR, provider: .qwenMessage, model: "fixture")
  let en = ModelConfiguration(purpose: .englishASR, provider: .assemblyAI, model: "fixture")
  let acoustic = ModelConfiguration(purpose: .audioReview, provider: .gemini, model: "fixture")
  try await store.configureFusionRequirements(ticket: ticket, configurations: [zh, en, acoustic])
  var initial: [RecognitionCandidate] = []
  for item in [zh, en] {
   let run = try await store.beginModelRun(ticket: ticket, configuration: item)
   let text = "支付15元。"
   let candidate = RecognitionCandidate(run: run, sequence: 1, text: text, stableUTF16Length: text.utf16.count, audioEndSeconds: 1, isComplete: true)
   _ = try await store.appendRecognitionCandidate(candidate)
   initial.append(candidate)
  }
  let old = PrecisionFusion.evaluate(candidates: initial, mode: .highestQuality, requiredConfigurationIDs: Set([zh.id,en.id]))
  let run = try await store.beginModelRun(ticket: ticket, configuration: acoustic)
  let corrected = "支付50元。"
  _ = try await store.appendRecognitionCandidate(RecognitionCandidate(run: run, sequence: 1, text: corrected, stableUTF16Length: corrected.utf16.count, audioEndSeconds: 1, isComplete: true))
  let current = try await store.latestRecognitionCandidates(ticket: ticket)
  let expected = PrecisionFusion.evaluate(candidates: current, mode: .highestQuality, requiredConfigurationIDs: Set([zh.id,en.id]))
  print("current_conflict_unresolved=\(expected.unresolved) current_safe_text=\(expected.stableText)")
  let result = try await store.publishFusion(ticket: ticket, proposal: old)
  print("old_proposal_published=\(result.published) deferred=\(result.deferred)")
  if let revision = try await store.latestDispatchableRevision(recordingID: record.id) {
   let reservation = try await store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count)
   print("stale_text_reservation=\(reservation?.text ?? "NONE")")
  } else { print("stale_text_reservation=NONE") }
 }
}
