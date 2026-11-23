import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path('/private/tmp/saytile-performance-022')
APP = Path('/tmp/saytile-022-final/Saytile.app')
OUT = Path('/Users/hhf/Documents/GitHub/saytile/dist/internal-0.22-567')
OUT.mkdir(parents=True, exist_ok=True)
DMG = OUT / 'Saytile-0.22-567-arm64.dmg'
assert not DMG.exists()
meta = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
assert meta['SaytileSourceRevision'] == 'a90601b79e59333c97982e200dfb69e541c2bf95'
assert meta['CFBundleVersion'] == '567' and not meta['SaytileSourceDirty']
receipt = dict(source=meta['SaytileSourceRevision'], version=meta['CFBundleShortVersionString'],
    build=meta['CFBundleVersion'], bundle_id=meta['CFBundleIdentifier'],
    verdict='HOLD / performance NO-GO', notarization='NOT_RUN: explicitly prohibited for this task',
    commands=[], installed_app_modified=False)
def run(args, allowed=(0,)):
    r = subprocess.run([str(x) for x in args], capture_output=True, text=True)
    receipt['commands'].append(dict(command=[str(x) for x in args], exit_code=r.returncode, stdout=r.stdout, stderr=r.stderr))
    assert r.returncode in allowed, (args[0], r.returncode, r.stderr[-1000:])
    return r
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
receipt['executable_sha256'] = sha(APP / 'Contents/MacOS/Saytile')
receipt['worker_sha256'] = sha(APP / 'Contents/Helpers/SaytileModelWorker')
assert receipt['worker_sha256'] == 'a1481a7bcead7e8ed8adc82a2804a040b923ffbe9459f9e3ce6cbc0187707a34'
run(['codesign', '--verify', '--deep', '--strict', APP])
run(['codesign', '-dvv', APP])
with tempfile.TemporaryDirectory(prefix='saytile-022-image-') as folder:
    folder = Path(folder)
    payload = folder / 'payload'
    payload.mkdir()
    run(['ditto', APP, payload / 'Saytile.app'])
    (payload / 'Applications').symlink_to('/Applications')
    (payload / '说明.txt').write_text('''Saytile 0.22（567）工程诊断候选

结论：HOLD / 性能优化 NO-GO。此包不是公开发行版。
两轮优化没有证明可重复的性能收益，已经撤回。识别算法保留 0.21 的行为。
该包仅用于工程复核；没有替换当前安装的 0.20（533）。
不要把本包覆盖到现有应用或资料目录。禁止通过关闭 Gatekeeper、移除 quarantine 等方法绕过系统安全。
已使用 Developer ID 签名；本轮按要求未提交公证，因此 Gatekeeper 可能拒绝。
原音、用户资料、Keychain 和模型缓存没有被打包或改动。
产品源码：a90601b79e59333c97982e200dfb69e541c2bf95
工程记录：https://github.com/haohongfei2001-png/saytile/pull/53
''')
    candidate = folder / 'candidate.dmg'
    run(['hdiutil','create','-volname','Saytile 0.22 (567)','-srcfolder',payload,'-format','UDZO',candidate])
    run(['codesign','--force','--timestamp','--sign','92B7E50A1D43D247EA7EA19A31DCA3E407435A42',candidate])
    run(['codesign','--verify','--strict',candidate])
    run(['hdiutil','verify',candidate])
    shutil.copyfile(candidate, DMG)
    mount = folder / 'mounted'
    mount.mkdir()
    run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',mount,DMG])
    try:
        mounted = mount / 'Saytile.app'
        run(['codesign','--verify','--deep','--strict',mounted])
        assert sha(mounted / 'Contents/MacOS/Saytile') == receipt['executable_sha256']
        assert sha(mounted / 'Contents/Helpers/SaytileModelWorker') == receipt['worker_sha256']
        copy = folder / 'isolated-install/Saytile.app'
        copy.parent.mkdir()
        run(['ditto',mounted,copy])
        run(['codesign','--verify','--deep','--strict',copy])
        assert sha(copy / 'Contents/MacOS/Saytile') == receipt['executable_sha256']
        run(['sandbox-exec','-p','(version 1)(allow default)(deny network*)',copy / 'Contents/MacOS/Saytile','--data-directory',folder / 'isolated-data','--smoke-test'])
        receipt['isolated_install_startup'] = 'PASS, copied from exact final DMG, disposable empty data, network denied'
    finally:
        run(['hdiutil','detach',mount])
for kind, args in [
    ('app', ['spctl','--assess','--type','execute','--verbose=4',APP]),
    ('dmg', ['spctl','--assess','--type','open','--context','context:primary-signature','--verbose=4',DMG])]:
    r = run(args, allowed=(0,1,2,3))
    receipt['gatekeeper_' + kind] = dict(status='PASS' if r.returncode == 0 else 'REJECTED', evidence=(r.stdout+r.stderr).strip())
receipt['dmg'] = str(DMG)
receipt['dmg_sha256'] = sha(DMG)
receipt['dmg_bytes'] = DMG.stat().st_size
(OUT / (DMG.name + '.sha256')).write_text(receipt['dmg_sha256'] + '  ' + DMG.name + '\n')
(ROOT / 'evidence/performance-022/final/package.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2))
(OUT / 'package.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2))
print(json.dumps({k:v for k,v in receipt.items() if k != 'commands'}, ensure_ascii=False))
