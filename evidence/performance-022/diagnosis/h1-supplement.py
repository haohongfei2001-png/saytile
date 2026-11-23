import json,runpy,time,plistlib
from pathlib import Path
r=Path('/private/tmp/saytile-performance-022'); out=r/'evidence/performance-022/h1-supplement';out.mkdir(exist_ok=False)
(out/'protocol.json').write_text(json.dumps({'reason':'Original pairs 2 and 3 missed unchanged load validity on baseline; retained. Two predeclared supplementary pairs, no further retry.', 'order':[['after','before'],['before','after']], 'initial_quiet_seconds':60,'inter_run_seconds':8},indent=2))
m=runpy.run_path(str(r/'scripts/mandarin/measure-preview-cost.py'))['public_run'];f=runpy.run_path(str(r/'scripts/mandarin/measure-loaded-preview.py'))['fixed_load'];s=runpy.run_path(str(r/'scripts/mandarin/score-live-cadence.py'))['measure']
apps={'before':Path('/private/tmp/saytile-release-021-app/Saytile.app'),'after':Path('/tmp/saytile-022-h1/Saytile.app')};manifest=r/'evidence/mandarin/continuous.json';base=Path('/private/tmp/saytile-release-021/.build');done=[]
time.sleep(60)
for i,order in enumerate([['after','before'],['before','after']],4):
 for a in order:
  name=f'pair-{i}-{a}'
  with f(Path('/private/tmp/saytile-021-cpu-load'),8,out/(name+'-load.json')):m(apps[a],manifest,'continuous-public-5',base/'local-asr/weights',base/'mandarin/wav',out/name)
  done.append((name,a));print(name,'saved',flush=True);time.sleep(8)
for name,a in done:
 sha=plistlib.loads((apps[a]/'Contents/Info.plist').read_bytes())['SaytileSourceRevision'];(out/name/'cadence.json').write_text(json.dumps(s(manifest,base/'mandarin/wav',out/name,sha),indent=2,ensure_ascii=False))
