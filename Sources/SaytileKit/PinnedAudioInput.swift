import Foundation
import CoreAudio
import CAudio

/// Explicit input selection is independent of the output device. The queue
/// delivers mono Float32 at its negotiated rate into the existing capture ring.
final class PinnedAudioInput {
    let sampleRate: Double
    private var handle: OpaquePointer?
    private var retainedRing: AudioRing?
    private var previousFrames: UInt64 = 0
    private var lastProgress = ContinuousClock.now

    init(device: AudioInputDevice) throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &rate) == noErr,
              rate.isFinite, (8_000...768_000).contains(rate) else { throw AudioFailure.message("所选麦克风未提供可用采样率") }
        var error: Int32 = 0
        guard let handle = st_input_open(device.uid, &rate, &error) else {
            throw AudioFailure.message("无法打开所选麦克风（\(error)），请确认设备连接")
        }
        self.handle = handle
        sampleRate = rate
    }

    // With no ring, the hardware acceptance probe only counts frames.
    func start(ring: AudioRing?) throws {
        guard let handle else { throw AudioFailure.message("所选麦克风已关闭") }
        retainedRing = ring
        let status = st_input_start(handle, ring?.pointer)
        guard status == 0 else { throw AudioFailure.message("无法启动所选麦克风（\(status)）") }
        lastProgress = .now
    }

    var frames: UInt64 { handle.map(st_input_frames) ?? 0 }

    func checkProgress() throws {
        guard let handle else { throw AudioFailure.message("所选麦克风已关闭") }
        let status = st_input_status(handle)
        guard status == 0 else { throw AudioFailure.message("所选麦克风已中断（\(status)），请确认设备后恢复") }
        let count = st_input_frames(handle)
        if count != previousFrames {
            previousFrames = count
            lastProgress = .now
        } else if lastProgress.duration(to: .now) >= .seconds(4) {
            throw AudioFailure.message("所选麦克风未提供音频，请确认设备后恢复")
        }
    }

    func stop() {
        if let handle { st_input_close(handle); self.handle = nil }
        retainedRing = nil
    }
    deinit { stop() }
}
