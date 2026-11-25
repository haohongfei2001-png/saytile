import subprocess, json, hashlib, datetime, os
from pathlib import Path
root=Path('/private/tmp/saytile-101-input')
e=root/'evidence/release-101/input-context-read/final'
out=Path('/private/tmp/saytile-context-read-final-build')
out.mkdir(exist_ok=True)
args=json.loads((root/'evidence/release-101/input/after-build.json').read_text())['arguments']
args[args.index('-emit-module-path')+1]=str(out/'SaytileKit.swiftmodule')
args[args.index('-o')+1]=str(out/'libSaytileKit.a')
record={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'arguments':['nice','-n','20']+args,'source_sha256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((root/'Sources/SaytileKit').glob('*.swift'))}}
with (e/'build.log').open('w') as f:
 r=subprocess.run(record['arguments'],cwd=root,stdout=f,stderr=subprocess.STDOUT,timeout=600)
record['exit_code']=r.returncode
(e/'build.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({'build_exit':r.returncode}),flush=True)
if r.returncode: raise SystemExit(r.returncode)
modulemap=next(a for a in args if a.startswith('-fmodule-map-file='))
for name in ['InputRoleReadProbe','InputWitnessSettlementProbe']:
 command=['nice','-n','20','swiftc','-swift-version','6','-parse-as-library','-I',str(root/'Sources/CSQLite'),'-I',str(out),'-Xcc',modulemap,'-L',str(out),'-lSaytileKit','-lc++','-module-cache-path',str(out/'clang-cache'),str(root/'tests/fixtures'/f'{name}.swift'),'-o',str(out/name)]
 with (e/f'{name}-compile.log').open('w') as f:
  r=subprocess.run(command,cwd=root,stdout=f,stderr=subprocess.STDOUT,timeout=120)
 (e/f'{name}-compile.json').write_text(json.dumps({'arguments':command,'exit_code':r.returncode,'fixture_sha256':hashlib.sha256((root/'tests/fixtures'/f'{name}.swift').read_bytes()).hexdigest()},indent=2)+'\n')
 print(json.dumps({'probe':name,'compile_exit':r.returncode}),flush=True)
 if r.returncode: raise SystemExit(r.returncode)
 with (e/f'{name}.json').open('w') as f:
  r=subprocess.run([str(out/name)],cwd=out,stdout=f,stderr=subprocess.PIPE,text=True,timeout=60)
 (e/f'{name}-stderr.log').write_text(r.stderr)
 print(json.dumps({'probe':name,'run_exit':r.returncode,'sha256':hashlib.sha256((out/name).read_bytes()).hexdigest()}),flush=True)
 if r.returncode: raise SystemExit(r.returncode)

command=[str(out/'InputRoleReadProbe'),'--page-context']
with (e/'InputContextReadProbe.json').open('w') as f:
 r=subprocess.run(command,cwd=out,stdout=f,stderr=subprocess.PIPE,text=True,timeout=60)
(e/'InputContextReadProbe-stderr.log').write_text(r.stderr)
print(json.dumps({'probe':'InputRoleReadProbe --page-context','run_exit':r.returncode}),flush=True)
raise SystemExit(r.returncode)
