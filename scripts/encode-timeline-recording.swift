// Encode only sampled frames from the synthetic app-owned window at their measured times.
import AppKit
import AVFoundation

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let times = try JSONDecoder().decode([Double].self, from: Data(contentsOf: source.appendingPathComponent("times.json")))
func frame(_ i: Int) throws -> CGImage {
    let path = source.appendingPathComponent("\(i).png")
    guard let decoder = CGImageSourceCreateWithURL(path as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(decoder, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
    return image
}
let first = try frame(0)
let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: first.width, AVVideoHeightKey: first.height])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: first.width, kCVPixelBufferHeightKey as String: first.height])
writer.add(input)
guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
writer.startSession(atSourceTime: .zero)
for (i, t) in times.enumerated() {
    while !input.isReadyForMoreMediaData && writer.status == .writing { try await Task.sleep(for: .milliseconds(5)) }
    var pixel: CVPixelBuffer?
    guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil,pool,&pixel) == kCVReturnSuccess,
          let pixel else { throw CocoaError(.fileWriteUnknown) }
    let image = try frame(i)
    CVPixelBufferLockBaseAddress(pixel, [])
    guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
        CVPixelBufferUnlockBaseAddress(pixel, []); throw CocoaError(.fileWriteUnknown)
    }
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    ctx.setFillColor(gray: 0.93, alpha: 1); ctx.fill(rect); ctx.draw(image, in: rect)
    CVPixelBufferUnlockBaseAddress(pixel, [])
    guard adaptor.append(pixel, withPresentationTime: CMTime(seconds: t, preferredTimescale: 60000)) else {
        throw writer.error ?? CocoaError(.fileWriteUnknown)
    }
}
input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
print("Native window recording: \(times.count) timestamped frames, \(times.last ?? 0)s")
