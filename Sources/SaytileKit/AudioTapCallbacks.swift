import CAudio
@preconcurrency import AVFoundation

/// Factories are deliberately nonisolated. AVAudioEngine invokes taps on its render
/// thread; an inherited MainActor closure traps at runtime under Swift 6.
enum AudioTapCallbacks {
    nonisolated static func recording(ring: AudioRing, channels: UInt32) -> AVAudioNodeTapBlock {
        { @Sendable buffer, _ in
            if let pointers = buffer.floatChannelData {
                st_ring_write(ring.pointer, pointers, channels, buffer.frameLength)
            }
        }
    }
    nonisolated static func counting(counter: AudioProbeCounter) -> AVAudioNodeTapBlock {
        { @Sendable buffer, _ in st_probe_count(counter.pointer, buffer.frameLength) }
    }
}
