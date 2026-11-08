#pragma once
#include <stdint.h>
#include <stddef.h>
typedef struct STAudioRing STAudioRing;
STAudioRing *st_ring_create(uint32_t capacity);
void st_ring_destroy(STAudioRing *ring);
// Single producer; Float32 planar PCM. No allocations, locks or IO.
void st_ring_write(STAudioRing *ring, const void *channel_pointers, uint32_t channel_count, uint32_t count);
uint32_t st_ring_read(STAudioRing *ring, float *output, uint32_t maximum);
uint64_t st_ring_dropped(STAudioRing *ring);
typedef struct STAudioProbe STAudioProbe;
STAudioProbe *st_probe_create(void);
void st_probe_destroy(STAudioProbe *probe);
void st_probe_count(STAudioProbe *probe, uint32_t frames);
uint64_t st_probe_frames(STAudioProbe *probe);
uint64_t st_probe_buffers(STAudioProbe *probe);
typedef struct STVAD STVAD;
STVAD *st_vad_create(void);
void st_vad_destroy(STVAD *vad);
int st_vad_process(STVAD *vad, const int16_t *pcm, size_t count);

// Audio Queue pins the input UID without also rebinding the engine's output.
// st_input_close synchronously ends callbacks before releasing the borrowed ring.
typedef struct STPinnedInput STPinnedInput;
STPinnedInput *st_input_open(const char *uid, double *sample_rate, int32_t *error);
int32_t st_input_start(STPinnedInput *input, STAudioRing *ring);
uint64_t st_input_frames(STPinnedInput *input);
int32_t st_input_status(STPinnedInput *input);
void st_input_close(STPinnedInput *input);
