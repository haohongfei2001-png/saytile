from pathlib import Path
import subprocess,json,hashlib,tempfile,plistlib,shutil
app=Path('/private/tmp/saytile-release101-public/Saytile.app');dmg=Path('/Users/hhf/Documents/GitHub/saytile/dist/1.0.1/Saytile-1.0.1-arm64.dmg');receipt={}
def run(args,success=True):
 r=subprocess.run([str(x) for x in args],capture_output=True,text=True,timeout=60)
 if success and r.returncode:raise RuntimeError(r.stderr)
 return {'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
with tempfile.TemporaryDirectory(prefix='saytile-release101-install-') as f:
 root=Path(f); mount=root/'mount';mount.mkdir();run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',mount,dmg])
 try:
  source=mount/'Saytile.app';assert source.exists(); target=root/'Applications/Saytile.app';target.parent.mkdir();run(['cp','-cR',source,target])
  files=['Contents/Info.plist','Contents/MacOS/Saytile','Contents/Helpers/SaytileModelWorker','Contents/Helpers/SaytileSherpa','Contents/Resources/default.metallib'];receipt['exact_tested_files']={}
  for name in files:
   digest=hashlib.sha256((app/name).read_bytes()).hexdigest();assert hashlib.sha256((target/name).read_bytes()).hexdigest()==digest;receipt['exact_tested_files'][name]=digest
  receipt['app_signature']=run(['codesign','--verify','--deep','--strict',target]);receipt['installed_info']=plistlib.loads((target/'Contents/Info.plist').read_bytes());receipt['offline_first_launch']=run(['sandbox-exec','-p','(version 1)(allow default)(deny network*)',target/'Contents/MacOS/Saytile','--data-directory',root/'empty-data','--smoke-test'])
  assert 'SAYTILE_SMOKE_OK records=0' in receipt['offline_first_launch']['stdout']
  resource=target/'Contents/Resources/SaytileBrandMark.png';resource.write_bytes(resource.read_bytes()+b'tamper-only-isolated-copy');receipt['tampered_resource_rejected']=run(['codesign','--verify','--deep','--strict',target],False);assert receipt['tampered_resource_rejected']['exit']!=0
 finally:run(['hdiutil','detach',mount])
receipt.update(status='PASS',source='73ad857442964437929819ba9965f6bcfdcefd27',scope='Read-only signed DMG -> isolated Applications -> offline empty store; exact tested executables and weights runtime; no installed 533 changes. Internet Gatekeeper is separately BLOCKED, no bypass.')
Path('evidence/release-101/install-dmg.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n');print('INSTALL_DMG_PASS')
