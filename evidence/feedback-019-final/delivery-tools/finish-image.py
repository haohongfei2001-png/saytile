"""Resume only a timestamp-failed image; never rebuild, install or weaken signature validation."""
import json, plistlib, sys
from pathlib import Path
import package as p
revision=sys.argv[1]
p.source(revision)
stage=Path('/private/tmp/saytile-feedback-release-'+revision[:8])
app=stage/'payload'/p.BUNDLE
meta=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert meta['SaytileSourceRevision']==revision and meta['SaytileSourceDirty'] is False
assert meta['CFBundleIdentifier']=='app.saytile.mac.mandarin-candidate'
frozen=json.loads((stage/'runtime484.json').read_text())
assert p.runtime(app)==frozen['files']
p.run('codesign','--verify','--deep','--strict',app)
image=stage/'Saytile-0.19-mandarin-arm64.dmg'
assert image.is_file() and not (stage/'package.json').exists() and not (stage/'installed').exists()
p.run('codesign','--force','--timestamp','--sign',p.IDENTITY,image)
p.run('codesign','--verify','--strict',image)
p.run('hdiutil','verify',image)
p.run('/bin/bash',p.TOOLS/'stage-image.sh',image,revision,stage/'installed')
staged=stage/'installed'/p.BUNDLE
assert p.runtime(staged)==frozen['files']
p.run('python3',p.TOOLS/'validate-image.py',staged,image,stage/'package.json')
receipt=json.loads((stage/'package.json').read_text())
assert receipt['source']==revision and receipt['worker_sha256']==p.WORKER and receipt['version']=='0.19'
p.source(revision)
(stage/'packaging-scope.json').write_text(json.dumps(dict(source=revision,baseline_source=p.BASE,version='0.19',runtime_original_source=p.RUNTIME_SOURCE,runtime_bytes_identical=True,asr_recompiled=False,update_configuration=receipt['update_configuration'],installed_app_read=False,production_app_read=False,private_data_read=False,installed=False,notarized=False,resumed_at='DMG timestamp only; failed signing log retained'),indent=2)+'\n')
print(stage)
