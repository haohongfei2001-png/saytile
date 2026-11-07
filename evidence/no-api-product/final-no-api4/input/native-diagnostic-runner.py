from pathlib import Path
import os,runpy,subprocess,hashlib,json,time,queue,threading
root=Path('/Users/hhf/.codex/worktrees/saytile-no-api-product');out=root/'evidence/no-api-product/final-no-api4/input'
m=runpy.run_path(str(root/'scripts/test-input-native.py'),run_name='input_native_diagnostic_import')
scratch=Path(os.environ['SAYTILE_INPUT_SCRATCH']); binary=scratch/'AXCoordinatorDiagnostic'
subprocess.run(['swiftc','-swift-version','6','-parse-as-library','-I',str(root/'Sources/CSQLite'),*m['production_flags'](),str(root/'tests/fixtures/AXFixtureActivationAudit.swift'),str(out/'AXCoordinatorDiagnostic.swift'),'-o',str(binary)],cwd=root,check=True)
paths=[binary,scratch/'AXTextFixture'];identities=[{'path':str(p),'sha256_before':hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]
f=subprocess.Popen([str(paths[1])],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);q=queue.Queue()
threading.Thread(target=m['lines_to_queue'],args=(f.stdout,'fixture',q),daemon=True).start()
try:
 name,line=q.get(timeout=10);print(line,end='',flush=True);assert line.strip()=='FIXTURE_READY'
 result=subprocess.run([str(binary),str(f.pid)],capture_output=True,text=True,timeout=30)
 print(result.stdout+result.stderr,flush=True);print('DIAGNOSTIC_EXIT',result.returncode,flush=True)
finally:
 f.terminate()
 try:f.wait(timeout=3)
 except subprocess.TimeoutExpired:f.kill();f.wait()
 for row in identities:row['sha256_after']=hashlib.sha256(Path(row['path']).read_bytes()).hexdigest();row['unchanged']=row['sha256_before']==row['sha256_after']
 (out/'diagnostic-binary-identities.json').write_text(json.dumps(identities,indent=2)+'\n')
