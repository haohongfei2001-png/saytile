#include "SaytileAudio.h"
#include "webrtc/common_audio/vad/include/webrtc_vad.h"
#include "webrtc/common_audio/vad/vad_core.h"
#include <stdlib.h>
struct STVAD { VadInst *instance; };
STVAD *st_vad_create(void){
 STVAD *v=calloc(1,sizeof(*v));if(!v)return NULL;
 v->instance=WebRtcVad_Create();
 if(!v->instance || WebRtcVad_Init(v->instance) || WebRtcVad_set_mode(v->instance,2)){st_vad_destroy(v);return NULL;}return v;
}
void st_vad_destroy(STVAD *v){if(v){WebRtcVad_Free(v->instance);free(v);}}
STVoiceFrame st_vad_process(STVAD *v, const int16_t *pcm, size_t count) {
  // The public WebRTC boolean includes the classifier's trailing hangover.
  // The vendored core keeps the original decision: 1 is fresh speech
  // evidence and values >1 extend speech that was detected earlier.
  if (!v || !pcm || WebRtcVad_Process(v->instance, 16000, pcm, count) <= 0) {
    return STVoiceQuiet;
  }
  return ((VadInstT *)v->instance)->vad == 1 ? STVoiceDetected : STVoiceHangover;
}
