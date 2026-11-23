import json,plistlib,runpy
from pathlib import Path
w=Path('/private/tmp/saytile-beta-021-20261123')
r=runpy.run_path(str(w/'scripts/mandarin/measure-preview-cost.py'))['public_run']
s=runpy.run_path(str(w/'scripts/mandarin/score-live-cadence.py'))['measure']
root=Path('/private/tmp/saytile-021-557-fixed15');root.mkdir(exist_ok=True)
manifest=w/'evidence/mandarin/panel-cohort.json'
rows=json.loads(manifest.read_text())['samples']
apps={'old':Path('/Users/hhf/Applications/Saytile.app'),'new':Path('/private/tmp/saytile-021-557-app/Saytile.app')}
for index,row in enumerate(rows):
 for arm in (['old','new'] if index%2==0 else ['new','old']):
  out=root/arm/row['id'];print('START',arm,row['id'],flush=True)
  r(apps[arm],manifest,row['id'],w/'.build/local-asr/weights',w/'.build/mandarin/wav',out)
  target=root/arm/('auto-qwen-small-'+row['id']+'.json')
  target.write_bytes((out/target.name).read_bytes())
for arm,app in apps.items():
 sha=plistlib.loads((app/'Contents/Info.plist').read_bytes())['SaytileSourceRevision']
 (root/arm/'cadence.json').write_text(json.dumps(s(manifest,w/'.build/mandarin/wav',root/arm,sha),ensure_ascii=False,indent=2))
print('FIXED15_DONE',flush=True)
