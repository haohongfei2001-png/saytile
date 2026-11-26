from pathlib import Path
import json, subprocess, runpy, time, traceback
r=Path('/private/tmp/saytile-release-101');e=r/'evidence/release-101/regression';e.mkdir(parents=True,exist_ok=True)
baseline=Path('/private/tmp/saytile-release100-final/Saytile.app');candidate=Path('/private/tmp/saytile-release101-final/Saytile.app')
manifest=Path('/private/tmp/saytile-experience-023/evidence/experience-023/setup/panel16.json');wav=Path('/private/tmp/saytile-beta-021-20261123/.build/mandarin/wav');weights=Path('/private/tmp/saytile-beta-021-20261123/.build/local-asr/weights')
rows=json.loads(manifest.read_text())['samples'];run=runpy.run_path(str(r/'scripts/mandarin/measure-preview-cost.py'))['public_run'];events=[]
def event(**data):
 data['wall_time']=time.time();events.append(data);(e/'progress.json').write_text(json.dumps(events,indent=2)+'\n');print(json.dumps(data),flush=True)
for i,row in enumerate(rows):
 arms=[('qwen-previous',baseline),('qwen-current',candidate)]
 if i%2:arms.reverse()
 for label,app in arms:
  out=e/'paired16'/label/row['id']
  try:run(app,manifest,row['id'],weights,wav,out)
  except Exception as err:
   event(phase='native',arm=label,sample=row['id'],status='FAIL',error=repr(err));(out/'failure.txt').write_text(traceback.format_exc())
  else:event(phase='native',arm=label,sample=row['id'],status='PASS')
try:
 subprocess.run(['python3',r/'scripts/mandarin/report-release-native.py','--root',e,'--manifest',manifest,'--audio',wav],cwd=r,check=True)
except Exception as err:event(phase='native-report',status='FAIL',error=repr(err))
for label,cli,app in [('baseline','/private/tmp/saytile-101-baseline-realtime-cohort',baseline),('candidate','/private/tmp/saytile-101-current-realtime-cohort',candidate)]:
 out=e/'quality';out.mkdir(exist_ok=True);event(phase='quality',arm=label,status='RUNNING')
 with (out/(label+'.log')).open('w') as log:
  p=subprocess.run([cli,'qwen-small','product',r/'evidence/release-101/setup/input440.json',wav,weights,app/'Contents/Helpers',out/(label+'-realtime440.jsonl'),'realtime'],cwd=app/'Contents/Resources',stdout=log,stderr=subprocess.STDOUT)
 event(phase='quality',arm=label,status='PASS' if p.returncode==0 else 'FAIL',exit_code=p.returncode)
event(phase='soak',status='RUNNING')
with (e/'soak.log').open('w') as log:
 p=subprocess.run(['python3',r/'scripts/mandarin/quality-soak.py','--app',candidate,'--weights',weights,'--wav',wav,'--manifest',manifest,'--output',e/'soak.json','--model','qwen-small','--automatic'],cwd=r,stdout=log,stderr=subprocess.STDOUT)
event(phase='soak',status='PASS' if p.returncode==0 else 'FAIL',exit_code=p.returncode)
event(phase='queue',status='COMPLETE')
