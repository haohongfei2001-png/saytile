import hashlib,json,pathlib,plistlib,subprocess,tempfile,shutil
R=pathlib.Path('/private/tmp/saytile-experience-023')
app=pathlib.Path('/private/tmp/saytile-023-571/Saytile.app')
product='a1ac008de50855ae0c03f30128f5b1f74269d617'
out=pathlib.Path('/Users/hhf/Documents/GitHub/saytile/dist/internal-0.23-571')
evidence=R/'evidence/experience-023/closure'
identity='92B7E50A1D43D247EA7EA19A31DCA3E407435A42'
installed=pathlib.Path('/Users/hhf/Applications/Saytile.app/Contents/MacOS/Saytile')
sha=lambda p:hashlib.file_digest(p.open('rb'),'sha256').hexdigest()
p=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert p['SaytileSourceRevision']==product and p['CFBundleVersion']=='571'
assert sha(installed)=='d711d1cab97d0ff20e23129269b8d72989db2e5258f659d49276f77cf9ab4737'
receipt=dict(source=product,version=p['CFBundleShortVersionString'],build=p['CFBundleVersion'],bundle=p['CFBundleIdentifier'],commands=[],notarization='NOT_RUN: prohibited by task',installed_533_before=sha(installed))
def save(): (evidence/'package.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
def run(cmd,check=True):
 r=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=240)
 receipt['commands'].append(dict(command=list(map(str,cmd)),exit=r.returncode,stdout=r.stdout,stderr=r.stderr));save()
 if check and r.returncode:raise RuntimeError(str(cmd[0])+': '+r.stderr)
 return r
out.mkdir(parents=True,exist_ok=True)
dmg=out/'Saytile-0.23-571-arm64.dmg'
assert not dmg.exists()
with tempfile.TemporaryDirectory(prefix='saytile-023-package-') as raw:
 t=pathlib.Path(raw); volume=t/'volume'; volume.mkdir()
 run(['codesign','--verify','--deep','--strict',app])
 run(['cp','-cR',app,volume/'Saytile.app'])
 (volume/'READ-ME.txt').write_text('Saytile 0.23 (571) - PR #54 internal engineering candidate\nSource: '+product+'\nDo not replace the installed 533. Use only an explicit isolated --data-directory.\nSigned Developer ID; NOT notarized by task instruction. Do not bypass Gatekeeper.\nNo public release, update feed, or user data is included.\n')
 run(['hdiutil','create','-volname','Saytile 0.23 (571)','-srcfolder',volume,'-format','UDZO',dmg])
 run(['codesign','--force','--timestamp','--sign',identity,dmg])
 run(['codesign','--verify','--strict',dmg]);run(['hdiutil','verify',dmg])
 for f in [app,dmg]:run(['codesign','-dv','--verbose=4',f])
 run(['spctl','--assess','--type','execute','--verbose=4',app],False)
 run(['spctl','--assess','--type','open','--context','context:primary-signature','--verbose=4',dmg],False)
 mount=t/'mount';mount.mkdir()
 run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',mount,dmg])
 try:
  tempapp=t/'Applications'/'Saytile.app';tempapp.parent.mkdir()
  run(['ditto',mount/'Saytile.app',tempapp])
  run(['codesign','--verify','--deep','--strict',tempapp])
  for relative in ['Contents/MacOS/Saytile','Contents/Helpers/SaytileModelWorker']:
   assert sha(tempapp/relative)==sha(app/relative)
  smoke=run(['sandbox-exec','-p','(version 1) (allow default) (deny network*)',tempapp/'Contents/MacOS/Saytile','--data-directory',t/'isolated-data','--smoke-test'])
  assert 'SAYTILE_SMOKE_OK' in smoke.stdout
  receipt['isolated_offline_launch']='PASS'
 finally:run(['hdiutil','detach',mount])
receipt.update(dmg=str(dmg),bytes=dmg.stat().st_size,sha256=sha(dmg),executable_sha256=sha(app/'Contents/MacOS/Saytile'),worker_sha256=sha(app/'Contents/Helpers/SaytileModelWorker'),installed_533_after=sha(installed))
assert receipt['installed_533_before']==receipt['installed_533_after']
save();shutil.copyfile(evidence/'package.json',out/'package.json')
(out/'SHA256SUMS.txt').write_text(receipt['sha256']+'  '+dmg.name+'\n')
shutil.copyfile('/private/tmp/saytile-023-build571.log',out/'build.log')
print(json.dumps({k:v for k,v in receipt.items() if k!='commands'},ensure_ascii=False,indent=2))
