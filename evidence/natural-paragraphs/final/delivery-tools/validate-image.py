import subprocess, plistlib, sys, json, hashlib, os
from pathlib import Path
app, image, out = map(Path, sys.argv[1:])
def run(*args):
    r=subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    return r.returncode,r.stdout.strip()
def digest(path):
    with path.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
verify_code,verify=run('codesign','--verify','--deep','--strict',str(app))
dcode,dresult=run('codesign','--verify','--strict',str(image))
rcode,display=run('codesign','-dv','--verbose=4',str(app))
acode,gate=run('spctl','--assess','--type','execute','--verbose=4',str(app))
signed_info=[l for l in display.splitlines() if l.startswith(('Identifier=','CodeDirectory','Authority=','Timestamp=','CDHash=','TeamIdentifier='))]
weights=[str(p.relative_to(app)) for p in app.rglob('*') if p.suffix.lower() in ('.safetensors','.onnx','.gguf','.mlmodelc')]
assert verify_code==dcode==rcode==0 and not weights
assert info['SaytileSourceDirty'] is False and info['CFBundleIdentifier']=='app.saytile.mac.mandarin-candidate'
assert any('runtime' in l for l in signed_info) and any('Developer ID Application' in l for l in signed_info)
result=dict(version=info['CFBundleShortVersionString'],build=info['CFBundleVersion'],source=info['SaytileSourceRevision'],
            bundle=info['CFBundleIdentifier'],app_executable_sha256=digest(app/'Contents/MacOS/Saytile'),
            worker_sha256=digest(app/'Contents/Helpers/SaytileModelWorker'),dmg_bytes=image.stat().st_size,dmg_sha256=digest(image),
            codesign_app='PASS',codesign_image='PASS',signing=signed_info,model_weights_in_bundle=weights,
            gatekeeper_exit=acode,gatekeeper_result=gate.replace(str(app),'Saytile 中文识别候选.app'),
            notarization_submitted=False, production_replaced=False)
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n'); print(json.dumps(result,ensure_ascii=False))
