from pathlib import Path
import plistlib,subprocess,tempfile,hashlib,json,os
root=Path.cwd();out=root/'evidence/no-api8/final';v=(root/'packaging/VERSION').read_text().strip();sha=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip();assert sha==os.environ['SAYTILE_EXPECTED_REVISION'];dmg=root/'dist'/('Saytile-'+v+'-arm64.dmg');dest=root/'dist/rc2-no-api.8/Saytile.app';assert not dest.exists();dest.parent.mkdir(parents=True,exist_ok=True)
run=lambda *a:subprocess.run([str(x) for x in a],check=True);h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory(prefix='saytile-final-noapi8-ro-') as tmp:
 mount=Path(tmp)/'mount';mount.mkdir();run('hdiutil','attach','-readonly','-nobrowse','-mountpoint',mount,dmg)
 try:
  raw=mount/'Saytile.app';run('codesign','--verify','--strict',raw);run('ditto','--norsrc',raw,dest)
 finally:run('hdiutil','detach',mount)
run('codesign','--verify','--strict',dest);info=plistlib.loads((dest/'Contents/Info.plist').read_bytes());b=dest/'Contents/MacOS/Saytile';sample=dest/'Contents/Resources/ConnectionSample.pcm';assert info['SaytileSourceRevision']==sha and info['SaytileSourceDirty'] is False and info['SaytileReleaseVersion']==v
r={'source_revision':sha,'tree':subprocess.check_output(['git','rev-parse','HEAD^{tree}'],text=True).strip(),'source_dirty':False,'version':v,'app_path':str(dest),'dmg_path':str(dmg),'binary_sha256':h(b),'dmg_sha256':h(dmg),'dmg_bytes':dmg.stat().st_size,'bundled_sample_bytes':sample.stat().st_size,'bundled_sample_sha256':h(sample),'architecture':subprocess.check_output(['file',str(b)],text=True).strip(),'signature':'ad-hoc; strict verify on mounted original and extracted App; not Developer ID notarized','installed_rc1_replaced':False,'cloud_calls':0};(out/'package-identity.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
