from pathlib import Path
import tempfile,subprocess,hashlib,sys,json,datetime
root=Path.cwd();out=Path(sys.argv[1]).resolve();out.mkdir(parents=True,exist_ok=True)
build=Path(sys.argv[2]).resolve()
cmd=['swift','build','--product','SaytileKit','--scratch-path',str(build),'-Xswiftc','-enable-testing']
subprocess.run(cmd,stdout=subprocess.DEVNULL,check=True);bindir=Path(subprocess.check_output(cmd+['--show-bin-path'],text=True).strip());module=bindir/'../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap'
if not module.exists():module=bindir/'CAudio.build/module.modulemap'
sha=lambda f:hashlib.sha256(Path(f).read_bytes()).hexdigest()
src=root/'tests/fixtures/PinnedDeviceAcceptance.swift'
meta={'source':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'version':(root/'packaging/VERSION').read_text().strip(),'source_changes':subprocess.check_output(['git','diff','--name-only','HEAD','--','Sources','tests','packaging'],text=True).splitlines(),'probe_source':sha(src),'library':sha(bindir/'libSaytileKit.a')}
with tempfile.TemporaryDirectory(prefix='saytile-explicit-final-') as raw:
 d=Path(raw);exe=d/'probe';args=['swiftc','-swift-version','6','-parse-as-library','-I',str(bindir),'-I',str(bindir/'Modules'),'-I',str(root/'Sources/CSQLite'),'-Xcc','-fmodule-map-file='+str(module.resolve()),'-L',str(bindir),'-lSaytileKit','-lc++',src,'-o',exe]
 subprocess.run(args,check=True);meta['probe']=sha(exe)
 for mode in ('duplex','input-only'):
  p=subprocess.run([exe,d/('store-'+mode),*(['--input-only'] if mode=='input-only' else [])],capture_output=True,text=True,timeout=60)
  receipt={**meta,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'mode':mode,'exit':p.returncode,'trace':p.stdout.splitlines(),'error':p.stderr[-2000:],'wavs':len(list((d/('store-'+mode)).rglob('*.wav')))}
  (out/(mode+'.json')).write_text(json.dumps(receipt,indent=2,ensure_ascii=False)+'\n')
  print(mode,p.returncode,p.stdout,flush=True)
  assert p.returncode==0 and 'PASS aggregate input backend' in p.stdout and 'REMOVAL' in p.stdout and receipt['wavs']==0
