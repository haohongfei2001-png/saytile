// Controlled competing compute for the local ASR soak. No network or audio access.
import Foundation
import Metal
import MetalPerformanceShaders
import Accelerate

let n = 768
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { exit(1) }
let descriptor = MPSMatrixDescriptor(rows: n, columns: n, rowBytes: n * 4, dataType: .float32)
func matrix() -> MPSMatrix {
    MPSMatrix(buffer: device.makeBuffer(length: n * n * 4, options: .storageModeShared)!, descriptor: descriptor)
}
let a = matrix(), b = matrix(), c = matrix()
let multiply = MPSMatrixMultiplication(device: device, resultRows: n, resultColumns: n, interiorColumns: n)
let seconds = Double(CommandLine.arguments[1])!
let end = ProcessInfo.processInfo.systemUptime + seconds
var x = [Float](repeating: 0.01, count: n*n), y = x, z = x
var cycles = 0
while ProcessInfo.processInfo.systemUptime < end {
    autoreleasepool {
        let command = queue.makeCommandBuffer()!
        for _ in 0..<16 { multiply.encode(commandBuffer: command, leftMatrix: a, rightMatrix: b, resultMatrix: c) }
        command.commit()
        vDSP_mmul(x, 1, y, 1, &z, 1, vDSP_Length(n), vDSP_Length(n), vDSP_Length(n))
        command.waitUntilCompleted()
        guard command.status == .completed else { exit(2) }
    }
    cycles += 1
    Thread.sleep(forTimeInterval: 0.035)
}
print("completed_compute_cycles", cycles, "requested_seconds", seconds)
