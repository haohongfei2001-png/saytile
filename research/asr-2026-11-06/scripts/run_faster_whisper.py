#!/usr/bin/env python3
"""Isolated offline baseline. No personal audio, no cloud upload, append-only results."""
import argparse, hashlib, json, platform, time
from pathlib import Path

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--manifest',required=True);ap.add_argument('--audio-root',required=True);ap.add_argument('--output',required=True);ap.add_argument('--model-dir',required=True);ap.add_argument('--language',default='auto');ap.add_argument('--threads',type=int,default=4);ap.add_argument('--limit',type=int);args=ap.parse_args()
    from faster_whisper import WhisperModel
    import soundfile as sf
    items=json.loads(Path(args.manifest).read_text()); items=items[:args.limit] if args.limit else items
    out=Path(args.output);out.parent.mkdir(parents=True,exist_ok=True)
    done={json.loads(l)['id'] for l in out.read_text().splitlines()} if out.exists() else set()
    started=time.monotonic();model=WhisperModel(args.model_dir,device='cpu',compute_type='int8',cpu_threads=args.threads,num_workers=1);load_seconds=time.monotonic()-started
    for i,item in enumerate(items):
        if item['id'] in done:continue
        p=Path(args.audio_root)/item['audio']; actual=hashlib.sha256(p.read_bytes()).hexdigest()
        if actual!=item['audio_sha256']:raise ValueError('audio hash mismatch: '+item['id'])
        t=time.monotonic();raw=[];err=None;text='';info_data={}
        try:
            audio,sr=sf.read(p,dtype='float32')
            if sr!=16000:raise ValueError('expected manifest 16 kHz PCM')
            segments,info=model.transcribe(audio,language=None if args.language=='auto' else args.language,task='transcribe',beam_size=5,temperature=0,condition_on_previous_text=True,vad_filter=False,word_timestamps=True)
            for seg in segments:
                raw.append(seg._asdict());text+=seg.text
            info_data={'language':info.language,'language_probability':info.language_probability,'duration':info.duration}
        except Exception as e:err=type(e).__name__+': '+str(e)
        result={'id':item['id'],'engine':'faster-whisper-large-v3-int8','model':'Systran/faster-whisper-large-v3','model_revision':'edaa852ec7e145841d8ffdb056a99866b5f0a478','configuration':{'audio_decoder':'soundfile-float32','device':'cpu','compute_type':'int8','language':args.language,'beam_size':5,'temperature':0,'vad_filter':False,'condition_on_previous_text':True},'audio_sha256':actual,'text':text,'segments':raw,'info':info_data,'error':err,'elapsed_seconds':time.monotonic()-t,'model_load_seconds':load_seconds,'first_readable_seconds':None,'stable_after_input_seconds':None,'latency_class':'offline_file_processing_not_realtime','platform':platform.platform()}
        with out.open('a') as f:f.write(json.dumps(result,ensure_ascii=False)+'\n');f.flush()
        print(json.dumps({'index':i+1,'id':item['id'],'seconds':round(result['elapsed_seconds'],2),'error':err},ensure_ascii=False),flush=True)
if __name__=='__main__':main()
