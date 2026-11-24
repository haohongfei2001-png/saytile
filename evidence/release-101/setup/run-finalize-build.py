from pathlib import Path
import time,json,runpy,subprocess,traceback,os,plistlib,hashlib
root=Path('/private/tmp/saytile-release-101');e=root/'evidence/release-101';start=time.monotonic()
while not (e/'post-regression.json').exists():
    if time.monotonic()-start>10800:raise TimeoutError('Sequential post-regression queue not complete')
    time.sleep(5)
# A second bounded contrast for the long-phrase tail seen in the original pair.
run=runpy.run_path(str(root/'scripts/mandarin/measure-preview-cost.py'))['public_run']
m=Path('/private/tmp/saytile-experience-023/evidence/experience-023/setup/panel16.json')
weights=Path('/private/tmp/saytile-beta-021-20261123/.build/local-asr/weights');audio=Path('/private/tmp/saytile-beta-021-20261123/.build/mandarin/wav')
rows=[];out=e/'long-tail-followup';out.mkdir(exist_ok=False)
for i in range(3):
    arms=[('baseline',Path('/private/tmp/saytile-release100-final/Saytile.app')),('candidate',Path('/private/tmp/saytile-release101-public/Saytile.app'))]
    if i%2:arms.reverse()
    for label,app in arms:
        target=out/f'pair-{i+1}'/label;result=dict(pair=i+1,arm=label,status='FAIL')
        try:run(app,m,'continuous-public-5',weights,audio,target);result['status']='PASS'
        except Exception:
            target.mkdir(parents=True,exist_ok=True);(target/'failure.txt').write_text(traceback.format_exc())
        rows.append(result);(out/'progress.json').write_text(json.dumps(rows,indent=2)+'\n');print(json.dumps(result),flush=True)
source=Path('/private/tmp/saytile-release101-product575');app=Path('/private/tmp/saytile-release101-575/Saytile.app');sha='8f25ea3be642263daf22ff297f337026395840a6'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip()==sha
assert not app.exists()
env=os.environ.copy();env.update(SAYTILE_BUILD_SCRATCH='/private/tmp/saytile-release101-575-build',SAYTILE_APP_OUTPUT=str(app),SAYTILE_SWIFT_DISABLE_SANDBOX='1',SAYTILE_VERIFIED_RUNTIME_APP='/private/tmp/saytile-023-571/Saytile.app',SAYTILE_DEVELOPER_ID='92B7E50A1D43D247EA7EA19A31DCA3E407435A42',SAYTILE_SIGN_IDENTITY='92B7E50A1D43D247EA7EA19A31DCA3E407435A42',SAYTILE_MANDARIN_CANDIDATE='1')
with open('/private/tmp/saytile-release101-build575.log','w') as log:subprocess.run(['bash','scripts/build-app.sh','release'],cwd=source,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
info=plistlib.loads((app/'Contents/Info.plist').read_bytes());assert info['SaytileSourceRevision']==sha and info['SaytileSourceDirty']==False and info['CFBundleVersion']=='575'
record={k:info[k] for k in ['CFBundleIdentifier','CFBundleShortVersionString','CFBundleVersion','SaytileSourceRevision','SaytileSourceDirty','SUPublicEDKey','SUFeedURL']};record['executableSHA256']=hashlib.sha256((app/'Contents/MacOS/Saytile').read_bytes()).hexdigest()
(e/'build/artifact-575.json').write_text(json.dumps(record,indent=2)+'\n')
with open('/private/tmp/saytile-release101-native575-controls.log','w') as log:subprocess.run(['python3',root/'scripts/test-native-ui.py','--app',app,'--output',e/'native575-controls','--controls'],cwd=root,stdout=log,stderr=subprocess.STDOUT,check=True)
print('FINAL_BUILD_AND_CONTROLS_COMPLETE',flush=True)
