import time,runpy,json,plistlib
from pathlib import Path
while not Path('/private/tmp/saytile-release-021-pressure-final.log').read_text().rstrip().endswith('FINAL_PAIR_DONE'):time.sleep(5)
# One final bounded pair after the unrelated inference/UI work and a quiet interval.
time.sleep(60)
w=Path('/private/tmp/saytile-release-021');root=Path('/private/tmp/saytile-release-021-native')
r=runpy.run_path(str(w/'scripts/mandarin/measure-preview-cost.py'))['public_run'];s=runpy.run_path(str(w/'scripts/mandarin/score-live-cadence.py'))['measure'];f=runpy.run_path(str(w/'scripts/mandarin/measure-loaded-preview.py'))['fixed_load']
for tag,app in [('closure-old-3',Path('/private/tmp/saytile-021-563-app/Saytile.app')),('closure-new-3',Path('/private/tmp/saytile-release-021-app/Saytile.app'))]:
 out=root/tag
 with f(Path('/private/tmp/saytile-021-cpu-load'),8,root/(tag+'-load.json')):r(app,w/'evidence/mandarin/continuous.json','continuous-public-5',w/'.build/local-asr/weights',w/'.build/mandarin/wav',out)
 sha=plistlib.loads((app/'Contents/Info.plist').read_bytes())['SaytileSourceRevision'];(out/'cadence.json').write_text(json.dumps(s(w/'evidence/mandarin/continuous.json',w/'.build/mandarin/wav',out,sha),ensure_ascii=False,indent=2))
print('CLOSURE_PAIR_DONE',flush=True)
