#include "SaytileAudio.h"
#include "webrtc/common_audio/vad/include/webrtc_vad.h"
#include <stdlib.h>
struct STVAD { VadInst *instance; };
STVAD *st_vad_create(void){
 STVAD *v=calloc(1,sizeof(*v));if(!v)return NULL;
 v->instance=WebRtcVad_Create();
 if(!v->instance || WebRtcVad_Init(v->instance) || WebRtcVad_set_mode(v->instance,2)){st_vad_destroy(v);return NULL;}return v;
}
void st_vad_destroy(STVAD *v){if(v){WebRtcVad_Free(v->instance);free(v);}}
int st_vad_process(STVAD *v,const int16_t *pcm,size_t count){return WebRtcVad_Process(v->instance,16000,pcm,count);}
