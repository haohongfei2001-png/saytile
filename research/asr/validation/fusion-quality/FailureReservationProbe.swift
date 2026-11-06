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
  _ = try await store.publishFusion(ticket: ticket, proposal: old)
  try await store.finishModelRun(initial[0].run, error: "fixture connection failed")
  if !CommandLine.arguments.contains("--hold-only"), let revision = try await store.latestDispatchableRevision(recordingID: record.id) {
   let before = try await store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count)
   print("failed_expert_before_retract_reservation=\(before?.text ?? "NONE")")
  }
  var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
  raw["stableText"] = try await store.fusionReservedPrefix(recordingID: record.id)
  raw["unresolved"] = true
  raw["reasonCode"] = "expert-failed-evidence-retained"
  let held = try JSONDecoder().decode(FusionProposal.self, from: JSONSerialization.data(withJSONObject: raw))
  let result = try await store.publishFusion(ticket: ticket, proposal: held)
  print("failure_hold_published=\(result.published) deferred=\(result.deferred)")
  if let revision = try await store.latestDispatchableRevision(recordingID: record.id) {
   let reservation = try await store.reserveDispatch(bindingID: binding, recordingID: record.id, revisionID: revision.id, stableUTF16End: revision.text.utf16.count)
   print("failed_expert_after_retract_reservation=\(reservation?.text ?? "NONE")")
  } else { print("failed_expert_after_retract_reservation=NONE") }
 }
}
