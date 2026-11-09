"""Apple's verification tools and isolated native UI on an independent GitHub Mac."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import runpy
import shutil
import subprocess
import time

assert os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_OS')=='macOS'
root=Path(os.environ['RUNNER_TEMP'])/'signed-package-evidence';root.mkdir()
temp=Path(os.environ['RUNNER_TEMP'])/'signed-package-test';temp.mkdir()
image=next(Path('deliverables/no-api.10').glob('*.dmg'))
expected=json.loads(Path('evidence/no-api10/final/app/identity.json').read_text())
def file_hash(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(*args,check=True):
    proc = subprocess.run(args,capture_output=True,text=True,timeout=140)
    if check and proc.returncode:
        raise RuntimeError(f'{args[0]} returned {proc.returncode}: '+(proc.stderr or proc.stdout)[-1200:])
    return proc
assert file_hash(image)==expected['dmg_sha256']
run('hdiutil','verify',image);run('codesign','--verify','--strict',image)
mount=temp/'mount';mount.mkdir()
app=temp/'Saytile.app'
def attach(dmg):run('hdiutil','attach','-readonly','-nobrowse','-noautoopen','-mountpoint',mount,dmg)
attach(image)
try:run('ditto','--norsrc',mount/'Saytile.app',app)
finally:run('hdiutil','detach',mount)
team = re.search(r'(?m)^TeamIdentifier=([A-Z0-9]{10})$',run('codesign','-dvvv',app).stderr)
assert team, 'expected a Developer ID team'
verify_signature = runpy.run_path('distribution/developer-id.py')['check_signature']
verify_signature(app,team[1],app=True)
verify_signature(image,team[1])
binary=app/'Contents/MacOS/Saytile';info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['SaytileSourceRevision']==expected['source'] and info['SaytileSourceDirty'] is False
assert file_hash(binary)==expected['binary_sha256']
ent=run('codesign','-d','--entitlements','-',app)
assert plistlib.loads(ent.stdout.encode())=={'com.apple.security.device.audio-input':True}
signed=dict(source=info['SaytileSourceRevision'],dmg_sha256=file_hash(image),binary_sha256=file_hash(binary),
            signature='Developer ID Application',audio_input_entitlement=True)
assert 'SAYTILE_SMOKE_OK' in run(binary,'--data-directory',temp/'smoke','--smoke-test').stdout
signed['isolated_launch']='PASS'
for script,args in [
    ('research/asr/validation/fusion-quality/check-probe-isolation.py',['--app',binary,'--output',root/'cli.json']),
    ('scripts/test-connection-setup.py',['--app',app,'--output',root/'connection.json']),
    ('scripts/test-native-ui.py',['--app',app,'--output',root/'ui'])]:
    run('python3',script,*args)
signed['isolated_native_controls']='PASS'
# Evaluate a distinct downloaded-file equivalent only. The assessed copy is never launched.
quarantined=temp/'downloaded.dmg';shutil.copyfile(image,quarantined)
run('xattr','-w','com.apple.quarantine',f'0083;{int(time.time()):x};SaytileAcceptance;',quarantined)
assert file_hash(quarantined)==signed['dmg_sha256']
dmg_assessment=run('spctl','--assess','--type','open','--context','context:primary-signature','--verbose=4',quarantined,check=False)
attach(quarantined)
try:
    a=run('spctl','--assess','--type','execute','--verbose=4',mount/'Saytile.app',check=False)
    signed.update(dmg_gatekeeper_exit=dmg_assessment.returncode,app_gatekeeper_exit=a.returncode,
                  app_unnotarized='Unnotarized Developer ID' in (a.stdout+a.stderr),
                  public_distribution='PASS' if a.returncode==0 and dmg_assessment.returncode==0 else 'BLOCKED')
finally:run('hdiutil','detach',mount)
(root/'signed-installation.json').write_text(json.dumps(signed,indent=2)+'\n')
