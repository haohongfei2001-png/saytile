"""Offline experiment only; does not modify scoring or production publication.
Uses the unchanged PreviewPolicyReplay executable and recorded public hypotheses.
Rejected whole-candidate throttles are kept to expose their latency tradeoff.
"""
import argparse,json,runpy,subprocess,hashlib
from pathlib import Path
cli=argparse.ArgumentParser(description=__doc__)
cli.add_argument('--replay',type=Path,required=True)
cli.add_argument('--audio',type=Path,required=True)
a=cli.parse_args()
R=Path(__file__).resolve().parents[2]; E=R/'evidence/experience-023'; out=E/'closure/replay-deep'; out.mkdir(parents=True,exist_ok=True)
sc=runpy.run_path(str(R/'scripts/mandarin/score-live-cadence.py')); rev=runpy.run_path(str(R/'scripts/mandarin/score-preview-reversals.py'))['reversals']; norm=sc['norm']
files=sorted((E/'final/paired16/qwen-preview').glob('*/visible-raw.json'))+sorted((E/'final/variance/continuous-public-5').glob('*/qwen-preview/native/visible-raw.json'))
replay=json.loads(subprocess.check_output([str(a.replay),*map(str,files)]))
refs={r['id']:r for r in json.loads((E/'setup/panel16.json').read_text())['samples']}

def deep_rewrite(before,after):
 a,b=norm(before),norm(after)
 common=next((i for i,(x,y) in enumerate(zip(a,b)) if x!=y),min(len(a),len(b)))
 return len(a)>=24 and common < len(a)-8

def throttle(events,period):
 result=[]; last=''; revision=-100; pending=None; due=None
 def emit(e):
  nonlocal last,revision
  if last and deep_rewrite(last,e['text']): revision=e['t']
  if e['text']!=last or e['kind']=='final':result.append(e)
  last=e['text']
 for e in events:
  if pending and due<=e['t']:
   emit(dict(pending,t=due));pending=None
  if e['kind']=='final':
   pending=None;emit(e);last='';revision=-100;continue
  if not last or not deep_rewrite(last,e['text']) or e['t']>=revision+period:
   pending=None;emit(e)
  else: pending=e;due=revision+period
 return result

def timeline(events):
 prefix=''; result=[]
 for e in events:
  result.append(dict(e,text=prefix+e['text']))
  if e['kind']=='final':prefix+=e['text']
 return result
rows=[]; dispatch=[]
for p,r in zip(files,replay):
 d=json.loads(p.read_text()); ident=next(i for i in refs if i in str(p)); ref=refs[ident]; onset,end=runpy.run_path(str(R/'scripts/score-local-asr.py'))['acoustic'](a.audio/(ident+'.wav'));end=min(end,d['endOfFile'])
 entry=dict(file=str(p.relative_to(R)),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),id=ident,policies={})
 for name,events in [('baseline',r['provisional']),('revision900',throttle(r['provisional'],.9)),('revision1200',throttle(r['provisional'],1.2))]:
  ts=sc['layer_events'](timeline(events),sc['bigrams'](ref['reference']),onset,end,False)[1]
  spans=sc['gaps']([onset,*ts,end])
  entry['policies'][name]=dict(aba=len(rev(events,end)),first=ts[0]-onset if ts else None,maxgap=max(spans),publications=len(events),events=events)
 rows.append(entry)
 segment=[]
 for e in d['rawWorkerEvents']:
  if e['kind']=='partial': segment.append(e)
  elif e['kind']=='final':
   for confirmations in [2,3,4]:
    granted='';conflicts=[]
    for idx in range(confirmations-1,len(segment)):
     strings=[z['text'] for z in segment[idx-confirmations+1:idx+1]]
     pref=''
     for chars in zip(*strings):
      if len(set(chars))>1:break
      pref+=chars[0]
     pref=pref[:-8] if len(pref)>8 else ''
     if len(pref)>len(granted) and pref.startswith(granted):
      granted=pref
      if not e['text'].startswith(pref):conflicts.append(dict(t=segment[idx]['t'],prefix=pref,final=e['text']))
    dispatch.append(dict(file=str(p.relative_to(R)),confirmations=confirmations,segment_final=e['text'],granted=granted,conflicts=conflicts))
   segment=[]
(out/'raw-policy-replay.json').write_text(json.dumps(rows,ensure_ascii=False,indent=1))
(out/'prefix-safety.json').write_text(json.dumps(dispatch,ensure_ascii=False,indent=1))
for subset in ['all','variance']:
 sel=[x for x in rows if subset=='all' or '/variance/' in x['file']]
 print(subset,len(sel))
 for n in ['baseline','revision900','revision1200']:
  v=[x['policies'][n] for x in sel];print(n,'ABA',sum(x['aba'] for x in v),'maxgap',round(max(x['maxgap'] for x in v),3),'varianceGaps',[round(x['maxgap'],3) for x in v] if subset=='variance' else '', 'delay',round(max(x['first']-r['policies']['baseline']['first'] for x,r in zip(v,sel)),3))
for c in [2,3,4]:
 a=[x for x in dispatch if x['confirmations']==c];print('prefix',c,'segments',len(a),'grants',sum(bool(x['granted']) for x in a),'conflicts',sum(bool(x['conflicts']) for x in a))
