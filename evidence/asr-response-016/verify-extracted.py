import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

source = Path('/private/tmp/saytile-response-final/Saytile 中文识别候选.app')
extracted = Path('/private/tmp/saytile-response-dmg-extracted/Saytile 中文识别候选.app')
out = Path('/private/tmp/saytile-response-evidence/evidence/asr-response-016')

def manifest(root):
    rows = []
    for p in sorted(root.rglob('*')):
        rel = str(p.relative_to(root))
        if p.is_symlink():
            rows.append([rel, 'symlink', str(p.readlink())])
        elif p.is_file():
            rows.append([rel, 'file', p.stat().st_mode & 0o777, hashlib.sha256(p.read_bytes()).hexdigest()])
    return rows

a, b = manifest(source), manifest(extracted)
assert a == b
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(extracted)], check=True, capture_output=True)
with tempfile.TemporaryDirectory(prefix='saytile-extracted-smoke-') as t:
    r = subprocess.run(['sandbox-exec', '-p', '(version 1)(allow default)(deny network*)',
                        str(extracted / 'Contents/MacOS/Saytile'), '--data-directory', t,
                        '--smoke-test'], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and 'SAYTILE_SMOKE_OK records=0' in r.stdout, (r.returncode, r.stdout, r.stderr)
    (out / 'extracted-smoke.log').write_text(r.stdout + r.stderr)
(out / 'bundle-manifest.json').write_text(json.dumps(a, ensure_ascii=False, indent=2) + '\n')
result = {'status': 'PASS', 'source': 'd0b2d87320fd4145fbaea756690066bca3718bab',
          'version': '0.16', 'build': '486', 'readonly_dmg_mount': True,
          'signed_bundle_files_and_links_equal': True, 'file_and_link_count': len(a),
          'bundle_manifest_sha256': hashlib.sha256((out / 'bundle-manifest.json').read_bytes()).hexdigest(),
          'launch': 'real extracted executable, empty isolated directory, smoke-test',
          'network': 'denied', 'capture': 'not started', 'existing_installs_touched': False}
(out / 'extracted-image-verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(result))
