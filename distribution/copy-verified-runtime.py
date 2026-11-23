#!/usr/bin/env python3
"""Reuse a known signed arm64 runtime only when its tracked build inputs are identical."""
import hashlib
from pathlib import Path
import plistlib
import subprocess
import sys

source, destination = (Path(arg).resolve(strict=True) for arg in sys.argv[1:])
repo = Path(__file__).resolve().parents[1]
info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
baseline = 'a1ac008de50855ae0c03f30128f5b1f74269d617'
if (info.get('SaytileSourceRevision') != baseline or info.get('SaytileSourceDirty') is not False
        or info.get('CFBundleIdentifier') != 'app.saytile.mac.mandarin-candidate'):
    sys.exit('Expected the signed 0.23 (571) runtime donor')
subprocess.run(['codesign', '--verify', '--deep', '--strict', '-R=anchor apple generic and certificate leaf[subject.OU] = "ZB9D4T66QB"', source], check=True)
subprocess.run(['git', '-C', repo, 'diff', '--exit-code', baseline, '--', 'native/LocalASR',
                'scripts/build-local-runtime.sh', 'scripts/prepare-local-runtime.sh'], check=True)
worker = source / 'Contents/Helpers/SaytileModelWorker'
with worker.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != 'fc6a05714209b3971bf1d06b9f2bbdff7e2a4f27e7d723b56d00a46f989d1e9c':
        sys.exit('Unexpected local model worker')
for relative in ['Helpers/SaytileSherpa', 'Helpers/SaytileModelWorker', 'Frameworks/libonnxruntime.dylib',
                 'Frameworks/libsherpa-onnx-c-api.dylib', 'Resources/default.metallib', 'Resources/LocalASRLicenses']:
    target = destination / 'Contents' / relative
    target.parent.mkdir(exist_ok=True)
    subprocess.run(['ditto', source / 'Contents' / relative, target], check=True)

# iconutil and the headless PNG encoder can create different ICNS containers.
# Keep the installed approved native artwork byte-for-byte when its inputs match.
brand_inputs = ['packaging/brand/SaytilePlate.png', 'scripts/encode-iconset.py']
if subprocess.run(['git', '-C', repo, 'diff', '--quiet', baseline, '--', *brand_inputs]).returncode == 0:
    icon = source / 'Contents/Resources/Saytile.icns'
    if hashlib.sha256(icon.read_bytes()).hexdigest() != '65f50b1645187adbe06540ef8ea884b4abbfa650b435eaf62d4b0c1f946cf166':
        sys.exit('Unexpected approved native app icon')
    subprocess.run(['ditto', icon, destination / 'Contents/Resources/Saytile.icns'], check=True)
