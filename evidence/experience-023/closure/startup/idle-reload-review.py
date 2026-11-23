import hashlib,json,runpy,wave
from pathlib import Path
R=Path('/private/tmp/saytile-experience-023');E=R/'evidence/experience-023/closure/startup';audio=Path('/private/tmp/saytile-closure-idle-audio');audio.mkdir(exist_ok=True)
ref=next(r for r in json.loads((R/'evidence/experience-023/setup/panel16.json').read_text())['samples'] if r['id']=='ascend-mixed-a0b0e736637c643c')
source=Path('/private/tmp/saytile-release-021/.build/mandarin/wav')/(ref['id']+'.wav');assert hashlib.sha256(source.read_bytes()).hexdigest()==ref['audio_sha256']
with wave.open(str(source)) as w:
 assert (w.getnchannels(),w.getframerate(),w.getsampwidth())==(1,16000,2)
 pcm=w.readframes(w.getnframes());duration=len(pcm)/32000
file=audio/'qwen-idle-reload.wav'
with wave.open(str(file),'wb') as w:
 w.setparams((1,2,16000,0,'NONE','not compressed'));w.writeframes(pcm+bytes(45*32000)+pcm)
manifest=E/'idle-manifest.json';manifest.write_text(json.dumps({'composition':{'original':ref,'silence_seconds':45,'count':2},'samples':[dict(ref,id='qwen-idle-reload',reference=ref['reference']+ref['reference'],duration=duration*2+45,audio_sha256=hashlib.sha256(file.read_bytes()).hexdigest())]},ensure_ascii=False,indent=2)+'\n')
run=runpy.run_path(str(R/'scripts/mandarin/measure-preview-cost.py'))['public_run']
run(Path('/private/tmp/saytile-023-571/Saytile.app'),manifest,'qwen-idle-reload',Path('/private/tmp/saytile-023-weights'),audio,E/'idle-reload',trace=True,model='qwen-small',automatic=False)
d=json.loads((E/'idle-reload/visible-raw.json').read_text());ready=[e for e in d['rawWorkerEvents'] if e['kind']=='ready'];final=[e for e in d['rawWorkerEvents'] if e['kind']=='final'];samples=json.loads((E/'idle-reload/process-samples.json').read_text())
quiet=[s for s in samples if duration+37 < s['t'] < duration+43]
released=bool(quiet) and all('worker' not in s['footprint'] for s in quiet)
result={'source':d['sha'],'diagnostic_trace':True,'not_a_paired_latency_benchmark':True,'ready_count':len(ready),'ready_events':ready,'finals':final,'released_during_quiet':released,'quiet_observations':quiet,'matching_repeat_final':len(final)==2 and final[0]['text']==final[1]['text'],'final_visible_matches':d['frames'][-1]['text']==''.join(reversed(d['archive']))}
result['pass']=released and len(ready)==2 and result['matching_repeat_final'] and result['final_visible_matches']
(E/'idle-reload/summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');assert result['pass'],result
