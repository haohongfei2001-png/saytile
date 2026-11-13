#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>

// Read CoreAudio's hardware-input level meter only. The callback recycles the
// opaque system buffer without accessing audio bytes or forwarding them to ASR.
static void recycle(void *context, AudioQueueRef queue, AudioQueueBufferRef buffer,
                    const AudioTimeStamp *time, UInt32 packets,
                    const AudioStreamPacketDescription *descriptions) {
    atomic_fetch_add((_Atomic unsigned *)context, 1);
    AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

static OSStatus property(AudioObjectID object, AudioObjectPropertySelector selector,
                         UInt32 size, void *value) {
    AudioObjectPropertyAddress address = {
        selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    return AudioObjectGetPropertyData(object, &address, 0, NULL, &size, value);
}

int main(void) {
    @autoreleasepool {
        if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] != AVAuthorizationStatusAuthorized) {
            puts("BLOCKED existing microphone authorization required");
            return 2;
        }
        AudioObjectPropertyAddress address = {
            kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
        };
        UInt32 size = 0;
        AudioObjectID system = kAudioObjectSystemObject;
        if (AudioObjectGetPropertyDataSize(system, &address, 0, NULL, &size) || !size) return 2;
        NSMutableData *ids = [NSMutableData dataWithLength:size];
        if (AudioObjectGetPropertyData(system, &address, 0, NULL, &size, ids.mutableBytes)) return 2;
        AudioDeviceID device = kAudioObjectUnknown, defaultInput = kAudioObjectUnknown;
        property(system, kAudioHardwarePropertyDefaultInputDevice, sizeof(defaultInput), &defaultInput);
        address.mSelector = kAudioDevicePropertyStreams;
        address.mScope = kAudioObjectPropertyScopeInput;
        for (NSUInteger index = 0; index < ids.length / sizeof(AudioDeviceID); ++index) {
            AudioDeviceID candidate = ((const AudioDeviceID *)ids.bytes)[index];
            UInt32 transport = 0, streamsSize = 0;
            if (!property(candidate, kAudioDevicePropertyTransportType, sizeof(transport), &transport) &&
                transport == kAudioDeviceTransportTypeBuiltIn &&
                !AudioObjectGetPropertyDataSize(candidate, &address, 0, NULL, &streamsSize) && streamsSize) {
                device = candidate;
                break;
            }
        }
        CFStringRef uid = NULL;
        Float64 rate = 0;
        if (device == kAudioObjectUnknown ||
            property(device, kAudioDevicePropertyNominalSampleRate, sizeof(rate), &rate) ||
            property(device, kAudioDevicePropertyDeviceUID, sizeof(uid), &uid) || !uid) {
            puts("BLOCKED built-in input unavailable");
            return 2;
        }
        AudioStreamBasicDescription pcm = {
            .mSampleRate = rate, .mFormatID = kAudioFormatLinearPCM,
            .mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            .mBytesPerPacket = 2, .mFramesPerPacket = 1, .mBytesPerFrame = 2,
            .mChannelsPerFrame = 1, .mBitsPerChannel = 16
        };
        AudioQueueRef queue = NULL;
        _Atomic unsigned buffers = 0;
        UInt32 enabled = 1;
        OSStatus error = AudioQueueNewInput(&pcm, recycle, &buffers, NULL, NULL, 0, &queue);
        if (!error) error = AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, &uid, sizeof(uid));
        CFStringRef actual = NULL;
        size = sizeof(actual);
        if (!error) error = AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentDevice, &actual, &size);
        BOOL pinned = !error && actual && CFEqual(uid, actual);
        if (actual) CFRelease(actual);
        CFRelease(uid);
        if (!pinned && !error) error = kAudioQueueErr_InvalidPropertyValue;
        if (!error) error = AudioQueueSetProperty(queue, kAudioQueueProperty_EnableLevelMetering, &enabled, sizeof(enabled));
        for (int i = 0; i < 3 && !error; ++i) {
            AudioQueueBufferRef buffer = NULL;
            error = AudioQueueAllocateBuffer(queue, (UInt32)(rate / 10) * 2, &buffer);
            if (!error) error = AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
        }
        if (!error) error = AudioQueueStart(queue, NULL);
        int metered = 0, aboveFloor = 0;
        float peak = -160, maxMean = -160;
        for (int i = 0; i < 20 && !error; ++i) {
            usleep(100000);
            AudioQueueLevelMeterState channel = {};
            size = sizeof(channel);
            error = AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentLevelMeterDB, &channel, &size);
            if (!error && isfinite(channel.mPeakPower) && isfinite(channel.mAveragePower)) {
                ++metered;
                if (channel.mPeakPower > -119.9f) ++aboveFloor;
                peak = fmaxf(peak, channel.mPeakPower);
                maxMean = fmaxf(maxMean, channel.mAveragePower);
            }
        }
        if (queue) { AudioQueueStop(queue, true); AudioQueueDispose(queue, true); }
        unsigned delivered = atomic_load(&buffers);
        printf("status=%s os_status=%d transport=built-in default_input=%s pinned_uid_match=%s sample_rate=%.0f channels=1 "
               "meter_intervals=20 valid_meter_intervals=%d intervals_above_minus_119_9_dBFS=%d delivered_buffers=%u peak_dBFS=%.2f max_mean_dBFS=%.2f "
               "pcm_bytes_read=0 pcm_bytes_saved=0 asr_runs=0\n",
               !error && delivered && metered ? "PASS" : "UNVERIFIED", (int)error, device == defaultInput ? "true" : "false", pinned ? "true" : "false",
               rate, metered, aboveFloor, delivered, peak, maxMean);
        return !error && delivered && metered ? 0 : 1;
    }
}
