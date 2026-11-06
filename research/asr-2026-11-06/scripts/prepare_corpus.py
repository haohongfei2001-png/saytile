#!/usr/bin/env python3
"""Rebuild licensed human-speech evaluation; selection is frozen before inference.
Dependencies: requests, pyarrow, soundfile, numpy; ffmpeg only for atempo variant.
Audio is kept outside git. Manifest contains original published references.
"""
import argparse, hashlib, io, json, random, re, subprocess
from pathlib import Path
import numpy as np
import pyarrow.parquet as pq
import requests
import soundfile as sf
SOURCES={
 'ascend':{'repo':'CAiRE/ASCEND','revision':'737e9800ae31be9932ba8464c80366559bd28424','path':'main/test-00000-of-00001.parquet','file':'ascend-test.parquet','license':'CC-BY-SA-4.0'},
 'fleurs-en':{'repo':'google/fleurs','revision':'70bb2e84b976b7e960aa89f1c648e09c59f894dd','path':'parquet-data/en_us/test-00000-of-00001.parquet','file':'fleurs-en_us-test.parquet','license':'CC-BY-4.0'},
 'fleurs-zh':{'repo':'google/fleurs','revision':'70bb2e84b976b7e960aa89f1c648e09c59f894dd','path':'parquet-data/cmn_hans_cn/test-00000-of-00001.parquet','file':'fleurs-cmn_hans_cn-test.parquet','license':'CC-BY-4.0'},
}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--cache',default='.test-data/asr');ap.add_argument('--out',default='research/asr-2026-11-06/corpus');a=ap.parse_args();cache=Path(a.cache);out=Path(a.out);audio=cache/'audio';audio.mkdir(parents=True,exist_ok=True);out.mkdir(parents=True,exist_ok=True)
 tables={};source_snapshot={}
 for name,s in SOURCES.items():
  path=cache/s['file'];url=f"https://huggingface.co/datasets/{s['repo']}/resolve/{s['revision']}/{s['path']}"
  if not path.exists():
   with requests.get(url,stream=True,timeout=120) as r:
    r.raise_for_status()
    with path.with_suffix('.download').open('wb') as f:
     for block in r.iter_content(1048576):f.write(block)
   path.with_suffix('.download').replace(path)
  tables[name]=pq.read_table(path).to_pylist();source_snapshot[name]={**s,'url':url,'archive_sha256':sha(path),'archive_bytes':path.stat().st_size}
 rng=random.Random(20261106);manifest=[];chosen=set();index={}
 def ident(name,row):return name+'-'+(str(row['id']) if name=='ascend' else Path(row['path']).stem)
 def emit(name,row,group,critical=None):
  key=ident(name,row)
  if key in chosen:return None
  chosen.add(key);ref=row['transcription'] if name=='ascend' else row['raw_transcription'];lang=row['language'] if name=='ascend' else ('en' if name.endswith('en') else 'zh')
  data,sr=sf.read(io.BytesIO(row['audio']['bytes']),dtype='float32',always_2d=False)
  if data.ndim==2:data=data.mean(axis=1)
  if sr!=16000:raise ValueError('Unexpected original rate')
  p=audio/(key+'.wav');sf.write(p,data,sr,subtype='PCM_16')
  item={'id':key,'audio':p.name,'audio_sha256':sha(p),'sample_rate':sr,'frames':len(data),'duration_seconds':len(data)/sr,'reference':ref,'source_reference_raw':ref,'source_dataset':name,'source_row_id':str(row['id']),'source_audio_filename':Path(row['path']).name,'source_revision':SOURCES[name]['revision'],'license':SOURCES[name]['license'],'language':lang,'group':group,'human_voice':True,'synthetic_perturbation':False,'speaker':str(row.get('original_speaker_id','not_published')),'topic':row.get('topic'),'critical':critical or []}
  manifest.append(item);index[key]=(data,item);return item
 def pool(name,lang=None):
  rows=[r for r in tables[name] if '[UNK]' not in r.get('transcription','') and 2<= (r.get('duration') or r.get('num_samples',0)/16000)<=20 and (lang is None or r.get('language')==lang)]
  # One recording per FLEURS sentence in the primary corpus, so repeated texts
  # do not give that source extra weight. Choice is deterministic.
  rng.shuffle(rows)
  if name!='ascend':
   seen=set();rows=[r for r in rows if not (r['id'] in seen or seen.add(r['id']))]
  return rows
 for lang,n in [('mixed',32),('zh',8),('en',8)]:
  for row in pool('ascend',lang)[:n]:emit('ascend',row,'primary')
 for name in ['fleurs-zh','fleurs-en']:
  for row in pool(name)[:24]:emit(name,row,'primary')
 # Prespecified challenge utterances, selected ONLY from human references.
 specific={'ascend':['00229','00304','01022','01031','01133','01142','00917','00922'],'fleurs-zh':['1734','1814','1901','1906'],'fleurs-en':['1710','1814','1698','1901']}
 for name,ids in specific.items():
  for wanted in ids:
   options=[r for r in tables[name] if str(r['id'])==wanted and '[UNK]' not in r.get('transcription','')]
   options.sort(key=lambda r:r['path'])
   for row in options:
    if ident(name,row) not in chosen:emit(name,row,'challenge');break
 # Human-reviewed lexical probes, not inferred semantic correctness. No prompt
 # is given to any ASR from these annotations.
 entity_terms=['computer engineering','dialogue system','chitchat','computer language','problem language','G P A','G math','Apple','METI','34','Hydrogen','protons','electrons','one proton','one electron','atoms','暗物质','氢离子','质子','电子','人工智能','计算机科学','并不是','不是','不完全是','不要','不能','零点零点一percent','五percent','AI']
 for item in manifest:
  item['critical']=[{'text':term,'type':'negation' if term in ['并不是','不是','不完全是','不要','不能'] else 'number' if term in ['34','零点零点一percent','五percent','one proton','one electron'] else 'term','accepted_forms':[term]} for term in entity_terms if term.casefold() in item['reference'].casefold()]
 # Robustness variants keep real speech and exact references. These are digital
 # perturbations, not recordings in actual noisy rooms.
 seeds=[]
 for lang in ['zh','en','mixed']:seeds.extend([x for x in manifest if x['group']=='primary' and x['language']==lang][:2])
 for source in seeds:
  data,_=index[source['id']]
  for variant in ['gain-minus20db','white-noise-15db','tempo-1.2']:
   key=source['id']+'--'+variant;p=audio/(key+'.wav')
   if variant=='gain-minus20db':y=data*.1
   elif variant=='white-noise-15db':
    local=np.random.default_rng(int(hashlib.sha256(key.encode()).hexdigest()[:16],16));rms=np.sqrt(np.mean(data.astype('float64')**2));y=data+local.normal(0,rms/(10**(15/20)),len(data));y=np.clip(y,-.999,.999)
   else:
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(audio/source['audio']),'-af','atempo=1.2',str(p)],check=True);y,_=sf.read(p,dtype='float32')
   if variant!='tempo-1.2':sf.write(p,y,16000,subtype='PCM_16')
   item={**source,'id':key,'audio':p.name,'audio_sha256':sha(p),'frames':len(y),'duration_seconds':len(y)/16000,'group':'robustness','parent_id':source['id'],'synthetic_perturbation':True,'perturbation':variant};manifest.append(item)
 # Two deterministic concatenations stress duration/boundaries, not natural
 # unbroken monologues. Padded boundaries are recorded explicitly.
 for lang in ['mixed','zh']:
  parts=[x for x in manifest if x['group']=='primary' and x['language']==lang][:10];pieces=[];spans=[];cursor=0
  for x in parts:
   d,_=index[x['id']];pieces.append(d);spans.append({'parent_id':x['id'],'start_frame':cursor,'end_frame':cursor+len(d)});cursor+=len(d);pieces.append(np.zeros(6400,dtype=np.float32));cursor+=6400
  y=np.concatenate(pieces);key='continuous-concatenation-'+lang;p=audio/(key+'.wav');sf.write(p,y,16000,subtype='PCM_16');manifest.append({'id':key,'audio':p.name,'audio_sha256':sha(p),'sample_rate':16000,'frames':len(y),'duration_seconds':len(y)/16000,'reference':' '.join(x['reference'] for x in parts),'language':lang,'group':'continuity','human_voice':True,'synthetic_perturbation':True,'perturbation':'concatenation-with-400ms-silence','source_spans':spans,'license':'CC-BY-SA-4.0' if lang=='mixed' else 'CC-BY-SA-4.0 + CC-BY-4.0','critical':[]})
 for kind in ['silence','quiet-noise']:
  key='negative-control-'+kind;y=np.zeros(80000,dtype=np.float32) if kind=='silence' else np.random.default_rng(20261106).normal(0,.001,80000).astype('float32');p=audio/(key+'.wav');sf.write(p,y,16000,subtype='PCM_16');manifest.append({'id':key,'audio':p.name,'audio_sha256':sha(p),'sample_rate':16000,'frames':len(y),'duration_seconds':5,'reference':'','language':'none','group':'negative-control','human_voice':False,'synthetic_perturbation':True,'license':'CC0-1.0','critical':[]})
 (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');(out/'sources.json').write_text(json.dumps(source_snapshot,ensure_ascii=False,indent=2)+'\n')
 latency=[x for lang in ['zh','en','mixed'] for x in manifest if x['group']=='primary' and x['language']==lang][:0]
 for lang in ['zh','en','mixed']:latency.extend([x for x in manifest if x['group']=='primary' and x['language']==lang][:4])
 (out/'latency-manifest.json').write_text(json.dumps(latency,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'cases':len(manifest),'minutes':sum(x['duration_seconds'] for x in manifest)/60,'primary_cases':sum(x['group']=='primary' for x in manifest),'audio_bytes':sum((audio/x['audio']).stat().st_size for x in manifest),'manifest_sha256':sha(out/'manifest.json')},indent=2))
if __name__=='__main__':main()
