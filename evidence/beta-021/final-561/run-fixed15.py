import json,plistlib,runpy
from pathlib import Path
w=Path('/private/tmp/saytile-beta-021-20261123')
r=runpy.run_path(str(w/'scripts/mandarin/measure-preview-cost.py'))['public_run']
s=runpy.run_path(str(w/'scripts/mandarin/score-live-cadence.py'))['measure']
root=Path('/private/tmp/saytile-021-561-fixed15');root.mkdir(exist_ok=True)
manifest=w/'evidence/mandarin/panel-cohort.json';rows=json.loads(manifest.read_text())['samples'];app=Path('/private/tmp/saytile-021-561-app/Saytile.app')
for row in rows:
 out=root/row['id'];print('START',row['id'],flush=True)
 r(app,manifest,row['id'],w/'.build/local-asr/weights',w/'.build/mandarin/wav',out)
 target=root/('auto-qwen-small-'+row['id']+'.json');target.write_bytes((out/target.name).read_bytes())
sha=plistlib.loads((app/'Contents/Info.plist').read_bytes())['SaytileSourceRevision']
(root/'cadence.json').write_text(json.dumps(s(manifest,w/'.build/mandarin/wav',root,sha),ensure_ascii=False,indent=2))
print('FIXED15_DONE',flush=True)
