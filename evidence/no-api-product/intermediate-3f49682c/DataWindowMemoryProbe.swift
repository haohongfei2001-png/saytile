import Foundation
let reset = CommandLine.arguments.contains("--reset")
var pending = Data()
let incoming = Data(repeating: 42, count: 1334)
for index in 0..<50_000 {
    pending.append(incoming)
    while pending.count >= 640 {
        let frame = Data(pending.prefix(640))
        precondition(frame.count == 640)
        pending.removeFirst(640)
    }
    if reset { pending = pending.withUnsafeBytes { Data($0) } }
    if index == 0 || index == 24_999 || index == 49_999 {
        print("iterations=\(index+1) count=\(pending.count) start_index=\(pending.startIndex) end_index=\(pending.endIndex)")
    }
}
