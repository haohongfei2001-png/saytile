import hashlib,json,plistlib,shutil,subprocess,tempfile,datetime
from pathlib import Path
root=Path.cwd();out=root/'evidence/no-api9.1/app';source='0a0cdecab8eb099e1dc3bb21b4c15ba5c30c93f0';version='1.0.0-rc.2-no-api.9.1';assert subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()==source
def run(*args):subprocess.run([str(a) for a in args],check=True)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
name=f'Saytile-{version}-arm64.dmg';image=root/'dist'/name;stage=root/'dist/rc2-no-api.9.1';stage.mkdir(exist_ok=True);app=stage/'Saytile.app'
run('hdiutil','verify',image)
with tempfile.TemporaryDirectory(prefix='saytile-91-mount-') as raw:
 mount=Path(raw);run('hdiutil','attach','-readonly','-nobrowse','-noautoopen','-mountpoint',mount,image)
 try:
  a=mount/'Saytile.app';run('codesign','--verify','--strict',a);assert not app.exists()
  run('ditto','--norsrc',a,app);assert digest(a/'Contents/MacOS/Saytile')==digest(app/'Contents/MacOS/Saytile')
 finally:run('hdiutil','detach',mount)
run('codesign','--verify','--strict',app)
info=plistlib.loads((app/'Contents/Info.plist').read_bytes());assert info['SaytileSourceDirty'] is False and info['SaytileSourceRevision']==source and info['SaytileReleaseVersion']==version
package=root/'deliverables/no-api.9.1';package.mkdir(exist_ok=True,parents=True);canonical=Path('/Users/hhf/Documents/GitHub/saytile/dist/rc2-no-api.9.1');canonical.mkdir(exist_ok=True)
for target in [package/name,canonical/name]:
 if not target.exists():shutil.copyfile(image,target)
 assert digest(target)==digest(image)
(dataset:=package/'SHA256SUMS.txt').write_text(digest(image)+'  '+name+'\n')
r={'source_revision':source,'tree':subprocess.check_output(['git','rev-parse','HEAD^{tree}'],text=True).strip(),'version':version,'source_dirty':False,'binary_sha256':digest(app/'Contents/MacOS/Saytile'),'dmg_sha256':digest(image),'dmg_bytes':image.stat().st_size,'app_path':str(app),'dmg_path':str(image),'canonical_dmg':str(canonical/name),'repo_dmg':str((package/name).relative_to(root)),'signature':'ad hoc, verified on read-only volume and extracted copy','utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
(out/'identity.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(r))
