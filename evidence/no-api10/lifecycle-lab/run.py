"""Owned loopback and permission checks on an ephemeral GitHub macOS VM against frozen sources."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import socket
import runpy
import subprocess
import time

source='5639058e6b178027861b18cc0521387487c919d5'
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
def can_route():
    # A connected UDP descriptor consults the routing table. This test sends zero packets.
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
        try:
            sock.connect(('192.0.2.1',9))
            return True
        except OSError:
            return False

def wait_for(proc,marker,seconds):
    until=time.monotonic()+seconds
    while time.monotonic()<until and proc.poll() is None:
        if marker.exists():return True
        time.sleep(.1)
    return marker.exists()

def exercise_guest_link(proc,data,receipt):
    if not wait_for(proc,data/'input-ready',30):
        receipt['reason']='owned capture device did not start'
        return
    route=run('/sbin/route','-n','get','default',check=False)
    match=re.search(r'(?m)^\s*interface:\s*(en[0-9]+)\s*$',route.stdout)
    if not match or not can_route():
        receipt['reason']='single removable virtual Ethernet route unavailable'
        return
    nic=match[1]
    # Independent restoration also runs if the controller exits during the exercise.
    watchdog=subprocess.Popen(['sudo','-n','/bin/sh','-c','sleep 18; /sbin/ifconfig "$1" up','restore',nic],
                              stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        receipt['before_routable']=True
        receipt['down_exit']=run('sudo','-n','/sbin/ifconfig',nic,'down',check=False).returncode
        time.sleep(.5)
        receipt['offline_before_play']=not can_route()
        (data/'play').touch()
        receipt['segment_opened']=wait_for(proc,data/'journal-open',10)
        receipt['offline_while_recording']=not can_route()
    finally:
        receipt['up_exit']=run('sudo','-n','/sbin/ifconfig',nic,'up',check=False).returncode
        (data/'restored').touch()
        watchdog.wait(timeout=24)
    for _ in range(50):
        if can_route():break
        time.sleep(.2)
    receipt['after_routable']=can_route()
    if not receipt['after_routable']:
        receipt.update(status='FAIL',reason='guest route did not recover')
    elif receipt['down_exit']==receipt['up_exit']==0 and receipt['offline_before_play'] and receipt['offline_while_recording']:
        receipt['status']='PASS' if receipt['segment_opened'] else 'FAIL'
    else:
        receipt['reason']='guest retained a usable route while its virtual interface was down'

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
    # Only this disposable Mac's own virtual NIC is eligible. Keep CI management traffic online outside the short capture interval.
    with subprocess.Popen([exe,data,fixture],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,
                          env=dict(os.environ,SAYTILE_DEDICATED_AUDIO_LAB='hosted-vm',SAYTILE_VM_LINK_CHECK='1')) as p:
        link = dict(source=source,status='BLOCKED',cloud=False,synthetic_only=True)
        try:
            exercise_guest_link(p,data,link)
        finally:
            (data/'play').touch()
            (data/'restored').touch()
            save(evidence/'network.json',link)
        p.wait(timeout=65)
    if (data/'capture.json').exists():result=json.loads((data/'capture.json').read_text())
    else:result=dict(status='FAIL',reason='lab process did not produce capture state')
    save(evidence/'capture.json',dict(**manifest,**result,exit=p.returncode))
    assert p.returncode==0 and result['status']!='FAIL',result
    if link['status']=='PASS':
        assert result['status']=='PASS' and result['first_frames']>0 and result['prior_wavs_byte_identical']
        link.update(original_frames=result['first_frames'],original_preserved_after_reconnect=True)
        save(evidence/'network.json',link)
    assert link['status']!='FAIL',link
failures=[]
for case in (perm,capture):
    try:case()
    except Exception as error:
        failures.append(case.__name__)
        save(evidence/(case.__name__+'-error.json'),dict(source=source,status='FAIL',error=str(error)[-600:]))
if failures:raise SystemExit('Failed independent lab cases: '+', '.join(failures))
