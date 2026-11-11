import CoreAudio
import IOKit
import IOKit.pwr_mgt

/// Apple silicon notebooks physically disconnect only their built-in microphone
/// when the lid closes. HAL can still say "alive" and deliver full-rate zeros.
enum MicrophoneLid {
    static let reason = "Mac 检测到合盖，内置麦克风已断开。请打开屏幕后恢复收音。"

    static func blocks(builtIn: Bool, readClosed: () -> Bool? = closed) -> Bool {
        // No reading, no lid, an external route, or a quiet room is not evidence of a disconnect.
        builtIn && readClosed() == true
    }

    static func closed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, kAppleClamshellStateKey as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue(),
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return (value as? Bool)
    }

    static func isBuiltIn(_ input: AudioDeviceID?) -> Bool {
        guard let input, input != kAudioObjectUnknown else { return false }
        return property(input, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBuiltIn
    }

    static var defaultInput: AudioDeviceID? {
        property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice)
    }

    private static func property(_ object: AudioObjectID, _ key: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: key, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        var result: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr ? result : nil
    }
}
