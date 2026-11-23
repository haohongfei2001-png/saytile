import json,plistlib,runpy
from pathlib import Path
w=Path('/private/tmp/saytile-beta-021-20261123')
r=runpy.run_path(str(w/'scripts/mandarin/measure-preview-cost.py'))['public_run']
s=runpy.run_path(str(w/'scripts/mandarin/score-live-cadence.py'))['measure']
f=runpy.run_path(str(w/'scripts/mandarin/measure-loaded-preview.py'))['fixed_load']
apps=[Path('/Users/hhf/Applications/Saytile.app'),Path('/private/tmp/saytile-021-final-app/Saytile.app')]
root=Path('/private/tmp/saytile-021-556-paired');root.mkdir(exist_ok=True)
for group in ['normal','loaded']:
 for tag,idx in [('old-1',0),('new-1',1),('new-2',1),('old-2',0)]:
  app=apps[idx];out=root/(group+'-'+tag)
  print('START '+out.name,flush=True)
  if group=='normal':
   r(app,w/'evidence/mandarin/continuous.json','continuous-public-5',w/'.build/local-asr/weights',w/'.build/mandarin/wav',out)
  else:
   with f(Path('/private/tmp/saytile-021-cpu-load'),9,root/(out.name+'-load.json')):
    r(app,w/'evidence/mandarin/continuous.json','continuous-public-5',w/'.build/local-asr/weights',w/'.build/mandarin/wav',out)
  sha=plistlib.loads((app/'Contents/Info.plist').read_bytes())['SaytileSourceRevision']
  (out/'cadence.json').write_text(json.dumps(s(w/'evidence/mandarin/continuous.json',w/'.build/mandarin/wav',out,sha),ensure_ascii=False,indent=2))
print('PAIRED_DONE',flush=True)
