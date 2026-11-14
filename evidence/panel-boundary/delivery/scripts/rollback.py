#!/usr/bin/env python3
"""Exercise 476 -> 0.14 -> 476 against generated data only; never read an installed archive."""
from pathlib import Path
import argparse,hashlib,json,plistlib,re,subprocess as sp
ROOT=Path('/private/tmp/saytile-window-boundary');BASE='0fbca1d892bbc8aa550c4439b8cfcb045af825ae';WORKER='9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e';NAME='Saytile 中文识别候选.app'
PROBE=Path('/private/tmp/saytile-011-frozen-process/probe');PROBE_SHA='bd2c057e228cd8f1f2285fe6526a0860a7398f114a6a7b0ee23b93e19fe68f68'
def digest(p):
 with p.open('rb')as f:return hashlib.file_digest(f,'sha256').hexdigest()
def meta(app):return plistlib.loads((app/'Contents/Info.plist').read_bytes())
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('source');a=p.parse_args();assert re.fullmatch('[0-9a-f]{40}',a.source)
 driver=ROOT/'scripts/mandarin/check-app-rollback.py'
 frozen=sp.run(['git','-C',ROOT,'show',a.source+':scripts/mandarin/check-app-rollback.py'],check=True,capture_output=True).stdout
 assert driver.read_bytes()==frozen,'Upgrade runner changed since selected source'
 stage=Path('/private/tmp/saytile-window-boundary-release-'+a.source[:8]);package=json.loads((stage/'package.json').read_text());assert package['source']==a.source and package['version']=='0.14' and package['worker_sha256']==WORKER
 old=stage/'baseline476'/NAME;new=stage/'installed'/NAME
 assert meta(old)['SaytileSourceRevision']==BASE and meta(old)['CFBundleVersion']=='476'
 assert meta(new)['SaytileSourceRevision']==a.source and meta(new)['CFBundleShortVersionString']=='0.14'
 assert all(meta(app)['CFBundleIdentifier']=='app.saytile.mac.mandarin-candidate' and meta(app)['SaytileSourceDirty'] is False for app in (old,new))
 assert digest(PROBE)==PROBE_SHA and not PROBE.is_symlink()
 assert all(digest(app/'Contents/Helpers/SaytileModelWorker')==WORKER for app in (old,new))
 assert digest(old/'Contents/MacOS/Saytile')=='8a54d7a5db4e113c1e1941160087c02b45ca112c3a507dde8e4fe24dc621c849'
 assert digest(new/'Contents/MacOS/Saytile')==package['app_executable_sha256']
 for app in (old,new):sp.run(['codesign','--verify','--deep','--strict',app],check=True)
 assert not (stage/'rollback.json').exists(),'Do not replace prior evidence'
 with (stage/'rollback.log').open('w') as log:
  sp.run(['python3',ROOT/'scripts/mandarin/check-app-rollback.py','--same-candidate-profile','--old',old,'--candidate',new,'--seed-probe',PROBE,'--output',stage/'rollback.json'],cwd=ROOT,stdout=log,stderr=sp.STDOUT,check=True)
 r=json.loads((stage/'rollback.json').read_text());assert r['status']=='PASS'
 assert [x['source']for x in r['identities']]==[BASE,a.source]
 assert [x['step']for x in r['steps']]==['old','candidate','old_reopened']
 print(json.dumps({'status':'PASS','source':a.source,'baseline':BASE,'receipt':str(stage/'rollback.json'),'installed_app_used':False,'user_data_used':False},indent=2))
if __name__=='__main__':main()
