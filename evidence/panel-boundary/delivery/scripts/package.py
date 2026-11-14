#!/usr/bin/env python3
"""Build a staged 0.14 image using the immutable signed 476 ASR runtime. Never install."""
from pathlib import Path
import argparse,hashlib,json,os,plistlib,re,shutil,subprocess as sp,tempfile
REPO=Path('/private/tmp/saytile-window-boundary')
TOOLS=Path(__file__).resolve().parent
BASE='0fbca1d892bbc8aa550c4439b8cfcb045af825ae'
WORKER='9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e'
PRIOR=Path('/Users/hhf/Documents/GitHub/saytile/dist/local-mandarin-0.13-476')
BUNDLE='Saytile 中文识别候选.app'
IDENTITY='92B7E50A1D43D247EA7EA19A31DCA3E407435A42'
def require(value,message):
 if not value:raise RuntimeError(message)
def run(*args,**kw):return sp.run(list(map(str,args)),check=True,**kw)
def output(*args,**kw):return run(*args,text=True,capture_output=True,**kw).stdout.strip()
def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def runtime(app):
 files=[f for folder in ('Helpers','Frameworks') for f in (app/'Contents'/folder).rglob('*') if f.is_file() or f.is_symlink()]
 files+=[app/'Contents/Resources/default.metallib']
 return {str(f.relative_to(app)):({'symlink':os.readlink(f)} if f.is_symlink() else {'sha256':digest(f)}) for f in sorted(files)}
def validate_old(app,receipt):
 require(not app.is_symlink(),'Baseline bundle cannot be a symlink')
 i=plistlib.loads((app/'Contents/Info.plist').read_bytes())
 require(i['SaytileSourceRevision']==receipt['source']==BASE and i['SaytileSourceDirty'] is False,'Wrong baseline source')
 require(i['CFBundleIdentifier']==receipt['bundle']=='app.saytile.mac.mandarin-candidate' and i['CFBundleShortVersionString']=='0.13' and i['CFBundleVersion']=='476','Wrong baseline identity')
 require(digest(app/'Contents/MacOS/Saytile')==receipt['app_executable_sha256'],'Baseline executable changed')
 require(digest(app/'Contents/Helpers/SaytileModelWorker')==receipt['worker_sha256']==WORKER,'Baseline worker changed')
 run('codesign','--verify','--deep','--strict',app)
def source(chosen):
 require(re.fullmatch('[0-9a-f]{40}',chosen),'Full source SHA required')
 require(output('git','-C',REPO,'symbolic-ref','HEAD')=='refs/heads/codex/panel-window-boundary','Wrong worktree branch')
 require(output('git','-C',REPO,'rev-parse','HEAD')==chosen,'HEAD differs from selected source')
 require(not output('git','-C',REPO,'status','--porcelain'),'Commit all source/WIP before packaging')
 require((REPO/'packaging/VERSION').read_text().strip()=='0.14','Wrong version')
 run('git','-C',REPO,'merge-base','--is-ancestor',BASE,chosen)
 # Runtime/identity reuse must not hide changed ASR, entitlement or profile code.
 run('git','-C',REPO,'diff','--exit-code',BASE,chosen,'--','native/LocalASR','Sources/SaytileKit/Resources/LocalASR','Sources/SaytileKit/LocalASRProvider.swift','Sources/SaytileKit/SaytileStorageProfile.swift','distribution/audio-input.plist','packaging/brand')
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source');a=parser.parse_args();source(a.source)
 receipt=json.loads((PRIOR/'package.json').read_text());image=PRIOR/'Saytile-0.13-mandarin-arm64.dmg'
 require(receipt['source']==BASE and receipt['worker_sha256']==WORKER,'Wrong durable baseline receipt')
 require(digest(image)==receipt['dmg_sha256']=='d66aeb66b038b553e7d7e7ec89d18572d5ef2b182e3619bbcce55f45e11b18b1','Durable image changed')
 stage=Path('/private/tmp/saytile-window-boundary-release-'+a.source[:8]);stage.mkdir() # never overwrite
 (stage/'baseline476').mkdir();baseline=stage/'baseline476'/BUNDLE
 with tempfile.TemporaryDirectory(prefix='saytile-014-base-volume-') as mount:
  run('hdiutil','verify',image)
  run('hdiutil','attach','-readonly','-noautoopen','-nobrowse','-mountpoint',mount,image)
  try:run('ditto',Path(mount)/BUNDLE,baseline)
  finally:run('hdiutil','detach',mount)
 validate_old(baseline,receipt);runtime_before=runtime(baseline)
 (stage/'runtime476.json').write_text(json.dumps({'source':BASE,'dmg_sha256':receipt['dmg_sha256'],'worker_sha256':WORKER,'files':runtime_before},indent=2)+'\n')
 scratch=Path('/private/tmp/saytile-window-boundary-app-build-'+a.source[:8])
 args=['swift','build','--scratch-path',str(scratch),'-c','release','--disable-sandbox','-Xswiftc','-F','-Xswiftc',str(baseline/'Contents/Frameworks'),'-Xlinker','-F','-Xlinker',str(baseline/'Contents/Frameworks'),'-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks']
 with (stage/'build.log').open('w') as log:run(*args,cwd=REPO,stdout=log,stderr=sp.STDOUT)
 bin_dir=Path(output(*args,'--show-bin-path',cwd=REPO))
 source(a.source)
 payload=stage/'payload';payload.mkdir();app=payload/BUNDLE;run('ditto',baseline,app)
 shutil.copy2(bin_dir/'Saytile',app/'Contents/MacOS/Saytile')
 # Refresh source-owned host resources; large ASR weights remain absent.
 for src,dst in [('Sources/SaytileApp/Resources/SaytileBrandMark.png','Resources/SaytileBrandMark.png'),('Sources/SaytileKit/Resources/ConnectionSample.pcm','Resources/ConnectionSample.pcm'),('THIRD_PARTY_NOTICES.md','Resources/THIRD_PARTY_NOTICES.md'),('Sources/CAudio/WEBRTC-LICENSE.txt','Resources/WEBRTC-LICENSE.txt')]:shutil.copy2(REPO/src,app/'Contents'/dst)
 meta=plistlib.loads((REPO/'packaging/Info.plist').read_bytes());meta.update(CFBundleIdentifier='app.saytile.mac.mandarin-candidate',CFBundleDisplayName='Saytile 中文识别候选',CFBundleShortVersionString='0.14',CFBundleVersion=output('git','-C',REPO,'rev-list','--count','HEAD'),SaytileReleaseVersion='0.14',SaytileSourceRevision=a.source,SaytileSourceDirty=False)
 require(int(meta['CFBundleVersion'])>476,'New candidate build must advance')
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps(meta,sort_keys=False))
 run('codesign','--force','--options','runtime','--timestamp','--entitlements',REPO/'distribution/audio-input.plist','--sign',IDENTITY,app)
 run('codesign','--verify','--deep','--strict',app)
 require(runtime(app)==runtime_before,'A frozen runtime byte changed during packaging')
 require(digest(app/'Contents/Helpers/SaytileModelWorker')==WORKER,'Frozen worker was re-signed or replaced')
 (payload/'Applications').symlink_to('/Applications')
 (payload/'安装与使用.txt').write_text('Saytile 0.14 隔离候选\n本文件是工程候选，不是正式发布。与现有中文识别候选使用相同独立 Bundle ID；不要与其他版本同时运行。\n本次只增加浮板/窗口边界设置及全屏共存，ASR 运行库逐字节沿用已验证的 0.13 (476)。\n需签名、升级/回退与原生验证完成后再由工程执行安装。未公证，不要求关闭 Gatekeeper。\n',encoding='utf-8')
 dmg=stage/'Saytile-0.14-mandarin-arm64.dmg'
 run('hdiutil','create','-volname','Saytile 0.14','-srcfolder',payload,'-format','UDZO',dmg)
 run('codesign','--force','--timestamp','--sign',IDENTITY,dmg);run('codesign','--verify','--strict',dmg);run('hdiutil','verify',dmg)
 run('/bin/bash',TOOLS/'stage-image.sh',dmg,a.source,stage/'installed')
 staged=stage/'installed'/BUNDLE
 require(runtime(staged)==runtime_before,'DMG extraction changed runtime')
 run('python3',TOOLS/'validate-image.py',staged,dmg,stage/'package.json')
 new=json.loads((stage/'package.json').read_text());require(new['worker_sha256']==WORKER and new['version']=='0.14' and new['source']==a.source,'Final identity mismatch')
 source(a.source)
 (stage/'packaging-scope.json').write_text(json.dumps(dict(source=a.source,baseline_source=BASE,version='0.14',runtime_bytes_identical=True,asr_recompiled=False,installed_app_read=False,production_app_read=False,private_data_read=False,installed=False,notarized=False),indent=2)+'\n')
 print(stage)
if __name__=='__main__':main()
