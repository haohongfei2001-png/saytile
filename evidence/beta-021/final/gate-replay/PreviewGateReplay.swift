import Foundation
@testable import SaytileKit
@main struct PreviewGateReplay {
 static func main() throws {
  var output: [String: Any] = [:]
  for path in CommandLine.arguments.dropFirst() {
   let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath:path))) as! [String:Any]
   let events = obj["rawWorkerEvents"] as! [[String:Any]]
   var old = BaselineLiveText(model:.qwen), new = LocalLiveText(model:.qwen)
   var accumulated = "", before:[[String:Any]] = [], after:[[String:Any]] = []
   for item in events {
    let kind = item["kind"] as! String, text = item["text"] as! String
    if kind == "ready" || text.isEmpty { continue }
    let final = kind == "final", t = item["t"] as! Double
    if old.accept(text, final:final) != nil { before.append(["t":t,"text":accumulated+old.presentation,"kind":kind]) }
    if new.accept(text, final:final) != nil { after.append(["t":t,"text":accumulated+new.presentation,"kind":kind]) }
    if final { accumulated += text; old = BaselineLiveText(model:.qwen); new = LocalLiveText(model:.qwen) }
   }
   output[path] = ["before":before,"after":after]
  }
  FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:output,options:[.sortedKeys]))
 }
}
