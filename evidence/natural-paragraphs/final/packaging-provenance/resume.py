"""Resume the already-built exact484 payload after timestamp service failure. No install."""
from pathlib import Path
import importlib.util,json,plistlib
spec=importlib.util.spec_from_file_location('delivery_package',Path(__file__).with_name('package.py'))
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
chosen='ab8545507c79640ec3f419e33467a0263c154844';p.source(chosen)
stage=Path('/private/tmp/saytile-natural-paragraphs-release-ab854550');payload=stage/'payload';app=payload/p.BUNDLE
before=json.loads((stage/'runtime478.json').read_text())['files']
meta=plistlib.loads((app/'Contents/Info.plist').read_bytes())
p.require(meta['SaytileSourceRevision']==chosen and meta['SaytileSourceDirty'] is False and meta['CFBundleVersion']=='484','Unexpected payload identity')
p.require(p.runtime(app)==before,'Runtime changed before timestamp retry')
p.require(not (stage/'package.json').exists() and not (stage/'Saytile-0.15-mandarin-arm64.dmg').exists(),'Do not replace completed packaging')
# Exactly one bounded retry; timestamp remains required.
p.run('codesign','--force','--options','runtime','--timestamp','--entitlements',p.REPO/'distribution/audio-input.plist','--sign',p.IDENTITY,app)
p.run('codesign','--verify','--deep','--strict',app)
p.require(p.runtime(app)==before,'Frozen runtime changed during signature retry')
(payload/'Applications').symlink_to('/Applications')
(payload/'安装与使用.txt').write_text('Saytile 0.15 隔离候选\n本文件是工程候选，不是正式发布。与现有中文识别候选使用相同独立 Bundle ID；不要与其他版本同时运行。\n本次整合自然段显示、语音档案段落编辑与连续回听，ASR 运行库逐字节沿用已验证的 0.14 (478)。\n需签名、升级/回退与原生验证完成后再由工程执行安装。未公证，不要求关闭 Gatekeeper。\n',encoding='utf-8')
dmg=stage/'Saytile-0.15-mandarin-arm64.dmg'
p.run('hdiutil','create','-volname','Saytile 0.15','-srcfolder',payload,'-format','UDZO',dmg)
p.run('codesign','--force','--timestamp','--sign',p.IDENTITY,dmg)
p.run('codesign','--verify','--strict',dmg);p.run('hdiutil','verify',dmg)
p.run('/bin/bash',p.TOOLS/'stage-image.sh',dmg,chosen,stage/'installed')
staged=stage/'installed'/p.BUNDLE;p.require(p.runtime(staged)==before,'DMG extraction changed runtime')
p.run('python3',p.TOOLS/'validate-image.py',staged,dmg,stage/'package.json')
new=json.loads((stage/'package.json').read_text());p.require(new['worker_sha256']==p.WORKER and new['source']==chosen,'Final identity mismatch');p.source(chosen)
(stage/'packaging-scope.json').write_text(json.dumps(dict(source=chosen,baseline_source=p.BASE,version='0.15',runtime_bytes_identical=True,asr_recompiled=False,installed_app_read=False,production_app_read=False,private_data_read=False,installed=False,notarized=False,timestamp_service_retry=1),indent=2)+'\n')
print(stage)
