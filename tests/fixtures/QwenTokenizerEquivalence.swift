import Foundation
import Darwin
@main enum Compare {
 static func clock() -> Double { var r=rusage();getrusage(RUSAGE_SELF,&r);return Double(r.ru_utime.tv_sec+r.ru_stime.tv_sec)+Double(r.ru_utime.tv_usec+r.ru_stime.tv_usec)/1e6 }
 static func main() throws {
  let url=URL(fileURLWithPath:CommandLine.arguments[1]);var rows:[[String:Any]]=[]
  for pair in 0..<3 {
   for opt in (pair % 2 == 0 ? [false,true] : [true,false]) {
    let start=ProcessInfo.processInfo.systemUptime, cpu=clock()
    if opt { let m=OptimizedTokenizer();try m.load(from:url) } else { let m=Qwen3Tokenizer();try m.load(from:url) }
    rows.append(["pair":pair+1,"optimized":opt,"wall":ProcessInfo.processInfo.systemUptime-start,"cpu":clock()-cpu])
   }
  }
  let a=Qwen3Tokenizer(),b=OptimizedTokenizer();try a.load(from:url);try b.load(from:url)
  for i in 0..<152000 { precondition(a.getToken(for:i)==b.getToken(for:i));if let t=a.getToken(for:i) {precondition(a.getTokenId(for:t)==b.getTokenId(for:t))};precondition(a.decode(tokens:[i])==b.decode(tokens:[i])) }
  let refs=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [[String:Any]]
  for r in refs {let t=r["reference"] as! String;precondition(a.encode(t)==b.encode(t));precondition(a.decode(tokens:a.encode(t))==b.decode(tokens:b.encode(t)))}
  let data=try JSONSerialization.data(withJSONObject:["rows":rows,"allTokenIDsEqual":152000,"referenceEncodesEqual":refs.count],options:[.sortedKeys,.prettyPrinted]);FileHandle.standardOutput.write(data)
 }
}
