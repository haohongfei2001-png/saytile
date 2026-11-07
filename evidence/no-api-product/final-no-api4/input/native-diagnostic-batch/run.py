from pathlib import Path
import os,runpy,subprocess,hashlib,json,time,queue,threading
root=Path('/Users/hhf/.codex/worktrees/saytile-no-api-product');out=root/'evidence/no-api-product/final-no-api4/input/native-diagnostic-batch'
m=runpy.run_path(str(root/'scripts/test-input-native.py'),run_name='input_native_diagnostic_import')
scratch=Path(os.environ['SAYTILE_INPUT_SCRATCH']);binary=scratch/'AXBufferedDiagnostic'
subprocess.run(['swiftc','-swift-version','6','-parse-as-library','-I',str(root/'Sources/CSQLite'),*m['production_flags'](),str(root/'tests/fixtures/AXFixtureActivationAudit.swift'),str(out/'AXBufferedDiagnostic.swift'),'-o',str(binary)],cwd=root,check=True)
paths=[binary,scratch/'AXTextFixture'];ids=[{'path':str(p),'sha256_before':hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths];results=[]
try:
 for i in range(12):
  f=subprocess.Popen([str(paths[1])],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);q=queue.Queue()
  threading.Thread(target=m['lines_to_queue'],args=(f.stdout,'fixture',q),daemon=True).start()
  try:
   name,line=q.get(timeout=10);assert line.strip()=='FIXTURE_READY'
   result=subprocess.run([str(binary),str(f.pid)],capture_output=True,text=True,timeout=30)
   log=result.stdout+result.stderr;(out/f'case-{i+1:02}.log').write_text(log)
   ok=result.returncode==0 and 'DIAGNOSTIC_RESULT result=confirmed' in log
   results.append({'case':i+1,'exit':result.returncode,'confirmed':ok,'log':f'case-{i+1:02}.log'})
   print(json.dumps(results[-1]),flush=True)
  finally:
   f.terminate()
   try:f.wait(timeout=3)
   except subprocess.TimeoutExpired:f.kill();f.wait()
  if not ok:break
finally:
 for row in ids:row['sha256_after']=hashlib.sha256(Path(row['path']).read_bytes()).hexdigest();row['unchanged']=row['sha256_before']==row['sha256_after']
 (out/'receipt.json').write_text(json.dumps({'maximum_new_targets':12,'stop_on_first_nonconfirmed':True,'in_memory_only_during_attempt':True,'extra_AX_reads':0,'fresh_target_each_case':True,'results':results,'binaries':ids},indent=2)+'\n')
