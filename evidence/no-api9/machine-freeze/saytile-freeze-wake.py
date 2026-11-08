from pathlib import Path
import datetime,subprocess,hashlib,json,sys,tempfile
out=Path('evidence/no-api9/machine-freeze').resolve()
meta=json.loads(Path('evidence/no-api9/final/local-vad-apple/identity.json').read_text())
interval=json.loads((out/'soak/interval.json').read_text())
d=Path(tempfile.mkdtemp(prefix='saytile-wake-watch-'))
src=out/'WakeProbe.swift'; cmd=meta['build_argv'][:];cmd[cmd.index('-module-cache-path')+1]=str(d/'cache');cmd[-3:]=[str(src),'-o',str(d/'probe')]
lib=Path(cmd[cmd.index('-L')+1])/'libSaytileKit.a'
h=lambda f:hashlib.sha256(Path(f).read_bytes()).hexdigest()
assert h(lib)==meta['library_sha256']
subprocess.run(cmd,check=True)
s={'source':meta['source_revision'],'library_sha256':h(lib),'probe_source_sha256':h(src),'probe_sha256':h(d/'probe'),'observer_start_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
for mode in ['controlled','passive']:
 log=out/(mode+'-wake.jsonl')
 assert not log.exists()
 r=subprocess.Popen([str(d/'probe'),mode,str(d/mode),str(log),str(interval['pid']),str(datetime.datetime.fromisoformat(interval['due_utc']).timestamp())],stdout=subprocess.DEVNULL)
 if mode=='controlled': assert r.wait(timeout=20)==0
 else:
  s['observer_pid']=r.pid
  (out/'wake-identity.json').write_text(json.dumps(s,indent=2)+'\n')
  print('Passive physical sleep observer installed for this run',flush=True)
  sys.exit(r.wait())
