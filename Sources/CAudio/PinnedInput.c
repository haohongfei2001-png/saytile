#include "SaytileAudio.h"
#include <AudioToolbox/AudioToolbox.h>
#include <stdatomic.h>
#include <errno.h>
#include <stdlib.h>

struct STPinnedInput {
    AudioQueueRef queue;
    CFStringRef uid;
    STAudioRing *ring; // NULL in the metadata-only acceptance probe.
    _Atomic bool stopping;
    _Atomic int32_t error;
    _Atomic uint64_t frames;
};

static void receive(void *context, AudioQueueRef queue, AudioQueueBufferRef buffer,
                    const AudioTimeStamp *time, UInt32 packets, const AudioStreamPacketDescription *descriptions) {
    STPinnedInput *input = context;
    if (atomic_load(&input->stopping) || atomic_load(&input->error)) return;
    if (buffer->mAudioDataByteSize % sizeof(float) || (buffer->mAudioDataByteSize && !buffer->mAudioData)) {
        atomic_store(&input->error, kAudioQueueErr_InvalidBuffer);
        return;
    }
    UInt32 frames = buffer->mAudioDataByteSize / sizeof(float);
    if (input->ring) {
        const float *samples = buffer->mAudioData;
        st_ring_write(input->ring, &samples, 1, frames);
    }
    atomic_fetch_add(&input->frames, frames);
    OSStatus result = AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    if (result && !atomic_load(&input->stopping)) atomic_store(&input->error, result);
}

static OSStatus check_uid(STPinnedInput *input) {
    CFStringRef current = NULL;
    UInt32 size = sizeof(current);
    OSStatus result = AudioQueueGetProperty(input->queue, kAudioQueueProperty_CurrentDevice, &current, &size);
    if (result == noErr && (!current || !CFEqual(current, input->uid))) result = kAudioQueueErr_InvalidDevice;
    if (current) CFRelease(current);
    return result;
}

static void route_changed(void *context, AudioQueueRef queue, AudioQueuePropertyID property) {
    STPinnedInput *input = context;
    if (!atomic_load(&input->stopping)) {
        OSStatus result = check_uid(input);
        if (result) atomic_store(&input->error, result);
    }
}

void st_input_close(STPinnedInput *input) {
    if (!input) return;
    atomic_store(&input->stopping, true);
    if (input->queue) AudioQueueDispose(input->queue, true);
    if (input->uid) CFRelease(input->uid);
    free(input);
}

STPinnedInput *st_input_open(const char *uid, double *sample_rate, int32_t *error) {
    STPinnedInput *input = calloc(1, sizeof(*input));
    if (!input) { *error = ENOMEM; return NULL; }
    atomic_init(&input->stopping, false);
    atomic_init(&input->error, noErr);
    atomic_init(&input->frames, 0);
    input->uid = CFStringCreateWithCString(NULL, uid, kCFStringEncodingUTF8);
    AudioStreamBasicDescription stream = { .mSampleRate=*sample_rate, .mFormatID=kAudioFormatLinearPCM,
        .mFormatFlags=kAudioFormatFlagsNativeFloatPacked, .mBytesPerPacket=sizeof(float),
        .mFramesPerPacket=1, .mBytesPerFrame=sizeof(float), .mChannelsPerFrame=1, .mBitsPerChannel=32 };
    OSStatus result = input->uid ? AudioQueueNewInput(&stream,receive,input,NULL,NULL,0,&input->queue) : kAudioQueueErr_InvalidParameter;
    if (!result) result = AudioQueueSetProperty(input->queue,kAudioQueueProperty_CurrentDevice,&input->uid,sizeof(input->uid));
    if (!result) result = check_uid(input);
    UInt32 size = sizeof(stream);
    if (!result) result = AudioQueueGetProperty(input->queue,kAudioQueueProperty_StreamDescription,&stream,&size);
    if (!result && !(stream.mSampleRate >= 8000 && stream.mSampleRate <= 768000
        && stream.mFormatID == kAudioFormatLinearPCM && stream.mBitsPerChannel == 32
        && stream.mFramesPerPacket == 1 && stream.mChannelsPerFrame == 1 && stream.mBytesPerFrame == sizeof(float)
        && (stream.mFormatFlags & kAudioFormatFlagIsFloat))) result = kAudioQueueErr_InvalidPropertyValue;
    if (!result) result = AudioQueueAddPropertyListener(input->queue,kAudioQueueProperty_CurrentDevice,route_changed,input);
    if (result) { *error=result; st_input_close(input); return NULL; }
    *sample_rate=stream.mSampleRate;
    return input;
}

int32_t st_input_start(STPinnedInput *input, STAudioRing *ring) {
    input->ring=ring;
    OSStatus result=check_uid(input);
    for (int i=0; !result && i<3; ++i) {
        AudioQueueBufferRef buffer=NULL;
        result=AudioQueueAllocateBuffer(input->queue,1024*sizeof(float),&buffer);
        if (!result) result=AudioQueueEnqueueBuffer(input->queue,buffer,0,NULL);
    }
    if (!result) result=AudioQueueStart(input->queue,NULL);
    if (!result) result=check_uid(input);
    return result;
}

uint64_t st_input_frames(STPinnedInput *input) { return atomic_load(&input->frames); }
int32_t st_input_status(STPinnedInput *input) {
    OSStatus error = atomic_load(&input->error);
    return error ? error : check_uid(input);
}
