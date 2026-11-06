import CAudio
@preconcurrency import AVFoundation

/// Factories are deliberately nonisolated. AVAudioEngine invokes taps on its render
/// thread; an inherited MainActor closure traps at runtime under Swift 6.
enum AudioTapCallbacks {
    nonisolated static func recording(ring: AudioRing, channels: UInt32, sampleRate: Double) -> AVAudioNodeTapBlock {
        { @Sendable buffer, _ in
            guard buffer.format.channelCount == channels,
                  buffer.format.sampleRate == sampleRate,
                  buffer.format.commonFormat == .pcmFormatFloat32,
                  !buffer.format.isInterleaved, let pointers = buffer.floatChannelData else {
                // A device transition must not use the old layout or clock rate.
                // Zero channels records a gap without reading PCM;
                // the worker seals saved audio and reports the discontinuity.
                st_ring_write(ring.pointer, nil, 0, buffer.frameLength)
                return
            }
            st_ring_write(ring.pointer, pointers, channels, buffer.frameLength)
        }
    }
    nonisolated static func counting(counter: AudioProbeCounter) -> AVAudioNodeTapBlock {
        { @Sendable buffer, _ in st_probe_count(counter.pointer, buffer.frameLength) }
    }
}
