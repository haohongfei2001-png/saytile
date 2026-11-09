#include "SaytileAudio.h"
#include <stdlib.h>
#include <stdatomic.h>
struct STAudioRing { float *samples; uint32_t capacity; _Atomic uint64_t read, write, dropped; };
STAudioRing *st_ring_create(uint32_t capacity) {
 STAudioRing *r=calloc(1,sizeof(*r)); if(!r) return NULL;
 r->samples=calloc(capacity,sizeof(float)); if(!r->samples){free(r);return NULL;}
 r->capacity=capacity; return r;
}
void st_ring_destroy(STAudioRing *r){if(r){free(r->samples);free(r);}}
void st_ring_write(STAudioRing *r,const void *channel_pointers,uint32_t nc,uint32_t count){
 const float *const *channels=channel_pointers;
 uint64_t w=atomic_load_explicit(&r->write,memory_order_relaxed);
 uint64_t rd=atomic_load_explicit(&r->read,memory_order_acquire);
 if(!nc || count>r->capacity-(w-rd)){atomic_fetch_add_explicit(&r->dropped,count,memory_order_relaxed);return;}
 for(uint32_t i=0;i<count;i++){float v=0;for(uint32_t c=0;c<nc;c++)v+=channels[c][i];r->samples[(w+i)%r->capacity]=v/nc;}
 atomic_store_explicit(&r->write,w+count,memory_order_release);
}
uint32_t st_ring_read(STAudioRing *r,float *out,uint32_t max){
 uint64_t rd=atomic_load_explicit(&r->read,memory_order_relaxed),w=atomic_load_explicit(&r->write,memory_order_acquire);
 uint32_t n=(uint32_t)(w-rd);if(n>max)n=max;
 for(uint32_t i=0;i<n;i++)out[i]=r->samples[(rd+i)%r->capacity];
 atomic_store_explicit(&r->read,rd+n,memory_order_release);return n;
}
uint32_t st_ring_pending(STAudioRing *r){
 uint64_t read=atomic_load_explicit(&r->read,memory_order_relaxed);
 return (uint32_t)(atomic_load_explicit(&r->write,memory_order_acquire)-read);
}
uint64_t st_ring_dropped(STAudioRing *r){return atomic_load_explicit(&r->dropped,memory_order_relaxed);}
struct STAudioProbe { _Atomic uint64_t frames, buffers; };
STAudioProbe *st_probe_create(void){return calloc(1,sizeof(STAudioProbe));}
void st_probe_destroy(STAudioProbe *p){free(p);}
void st_probe_count(STAudioProbe *p,uint32_t frames){atomic_fetch_add(&p->frames,frames);atomic_fetch_add(&p->buffers,1);}
uint64_t st_probe_frames(STAudioProbe *p){return atomic_load(&p->frames);}
uint64_t st_probe_buffers(STAudioProbe *p){return atomic_load(&p->buffers);}
