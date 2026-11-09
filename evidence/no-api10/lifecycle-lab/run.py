"""Owned loopback and permission checks on an ephemeral GitHub macOS VM against frozen sources."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import runpy
import subprocess
import time

source='53f65d32aff3a7f82ea929591b8202a82aa4ee97'
def run(*argv,timeout=120,check=True):
    return subprocess.run(argv,capture_output=True,text=True,timeout=timeout,check=check)
def save(file,data): file.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def sha(file):return hashlib.sha256(file.read_bytes()).hexdigest()
assert os.getenv('GITHUB_ACTIONS')=='true' and os.getenv('SAYTILE_HOST_TYPE')=='github-hosted'
assert run('sysctl','-n','hw.model').stdout.strip().startswith('VirtualMac')
assert run('git','rev-parse','HEAD').stdout.strip()==source
harness=Path(__file__).resolve().parent
scratch=Path(os.environ['RUNNER_TEMP'])/'single-physical-lab';scratch.mkdir()
evidence=Path(os.environ['RUNNER_TEMP'])/'audio-proof';evidence.mkdir()
flags=runpy.run_path('scripts/test-input-native.py')['production_flags']()
def compile_swift(name,out):
    run('swiftc','-swift-version','6','-parse-as-library','-I','Sources/CSQLite',*flags,harness/(name+'.swift'),'-o',out)
def perm():
    bundle=scratch/'PermissionState.app'; mac=bundle/'Contents/MacOS';mac.mkdir(parents=True)
    compile_swift('Permission',mac/'PermissionState')
    bundleid='app.saytile.hosted.freeze.permission'
    with (bundle/'Contents/Info.plist').open('wb') as f:
        plistlib.dump(dict(CFBundleIdentifier=bundleid,CFBundleExecutable='PermissionState',CFBundleName='Saytile Private Permission Fixture',
             CFBundleVersion='1',CFBundlePackageType='APPL',LSBackgroundOnly=True,NSMicrophoneUsageDescription='Disposable no-prompt permission test'),f)
    run('codesign','--force','--sign','-',bundle)
    def observe(label):
        out=scratch/(label+'.json')
        run('open','-n','-g','-W',bundle,'--args',scratch/(label+'-db'),out,timeout=35)
        row=json.loads(out.read_text())
        assert not row['running'] and row['records']==0 and row['before']==row['after']
        return row
    pre=observe('before')
    result=dict(source=source,baseline=pre,status='BLOCKED',restoration='BLOCKED',grant_requested=False)
    if pre['before']==3:
        attempt=run('tccutil','reset','Microphone',bundleid,check=False)
        result['scoped_reset_exit']=attempt.returncode
        post=observe('after');result['after_scoped_reset']=post
        if attempt.returncode==0 and post['before']!=3 and post['permission_issue']:result['status']='PASS'
    else: result['reason']='unique bundled helper has no previous grant to revoke'
    save(evidence/'permission.json',result)
def capture():
    fixture=Path('evidence/no-api-product/intermediate-d4b9dbe/local/realtime-synthetic-source.aiff')
    assert sha(fixture)=='d7deb6ef7c7a6cc330fbb4ee82eb2733f82ee7761634e6df55f650037bf0b751'
    manifest=dict(source=source,fixture_sha256=sha(fixture),driver='BlackHole 2ch',machine='dedicated hosted virtual Mac')
    install=run('brew','install','--cask','blackhole-2ch',timeout=240,check=False)
    manifest['install_exit']=install.returncode
    if install.returncode!=0:
        save(evidence/'capture.json',dict(**manifest,status='BLOCKED',reason='loopback installer refused'))
        print(install.stderr[-1200:]);return
    # The runner is disposable. Only the new guest driver is used to produce and capture the synthetic signal.
    run('sudo','-n','launchctl','kickstart','-k','system/com.apple.audio.coreaudiod',check=False)
    time.sleep(4)
    exe=scratch/'capture';compile_swift('ControlledCapture',exe); manifest['probe_sha256']=sha(exe)
    data=scratch/'capture-data';data.mkdir()
    p=subprocess.run([exe,data,fixture],timeout=100,capture_output=True,text=True,
                     env=dict(os.environ,SAYTILE_DEDICATED_AUDIO_LAB='hosted-vm'))
    if (data/'capture.json').exists():result=json.loads((data/'capture.json').read_text())
    else:result=dict(status='FAIL',reason='lab process did not produce capture state')
    save(evidence/'capture.json',dict(**manifest,**result,exit=p.returncode))
    assert p.returncode==0 and result['status']!='FAIL',result
failures=[]
for case in (perm,capture):
    try:case()
    except Exception as error:
        failures.append(case.__name__)
        save(evidence/(case.__name__+'-error.json'),dict(source=source,status='FAIL',error=str(error)[-600:]))
if failures:raise SystemExit('Failed independent lab cases: '+', '.join(failures))
