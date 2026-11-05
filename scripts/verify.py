#!/usr/bin/env python3
"""Repeatable local validation. Does not access microphone or other apps."""
from pathlib import Path
import argparse,json,shutil,subprocess,sys,tempfile,platform
R=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--ui',action='store_true');args=p.parse_args()
(R/'evidence').mkdir(exist_ok=True)
runs=[]
def run(name,command,output):
 r=subprocess.run(command,cwd=R,text=True,capture_output=True)
 (R/'evidence'/output).write_text(r.stdout+r.stderr)
 runs.append({'name':name,'exit_code':r.returncode,'command':command,'output':'evidence/'+output})
 print(name,'PASS' if r.returncode==0 else 'FAIL')
 return r
run('inherited_pcm_sqlite',[sys.executable,'archive/recovery-source/handoff/reliability_lab.py'],'inherited-reliability.json')
run('reconstructed_contracts',[sys.executable,'tests/test_recovery_contracts.py'],'rebuilt-contracts.log')
if shutil.which('swiftc'):
 run('swift6_typecheck',['swiftc','-swift-version','6','-typecheck','contracts/Contracts.swift'],'swift-typecheck.log')
 with tempfile.TemporaryDirectory(prefix='saytile-swift-') as temp:
  binary=str(Path(temp)/'unicode-smoke')
  compiled=run('swift_smoke_build',['swiftc','-swift-version','6','contracts/Contracts.swift','tests/SwiftSmoke.swift','-o',binary],'swift-smoke-build.log')
  if compiled.returncode==0:run('swift_unicode_smoke',[binary],'swift-smoke.log')
else:runs.append({'name':'swift','result':'NOT_RUN','reason':'swiftc unavailable'})
if args.ui:run('prototype_dom',[sys.executable,'tests/prototype_checks.py'],'prototype-checks.log')
else:runs.append({'name':'prototype_dom','result':'NOT_RUN','reason':'--ui not supplied'})
report={'scope':'Synthetic design and DOM validation, not native product acceptance','platform':platform.platform(),'python':platform.python_version(),'runs':runs,'success':all(r.get('exit_code',0)==0 for r in runs)}
(R/'evidence/verification.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
sys.exit(not report['success'])
