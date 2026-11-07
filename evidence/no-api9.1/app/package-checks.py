from pathlib import Path
import datetime,sqlite3,hashlib,subprocess,json,tempfile,sys
root=Path.cwd();out=root/'evidence/no-api9.1';m=json.loads((out/'app/identity.json').read_text())
app=Path(m['app_path']);binary=app/'Contents/MacOS/Saytile';h=lambda f:hashlib.sha256(Path(f).read_bytes()).hexdigest()
assert h(binary)==m['binary_sha256']
def save(path,data):
 data.update(source=m['source_revision'],binary=m['binary_sha256'],dmg=m['dmg_sha256'],utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
 (out/path).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def execute(cmd,timeout=60):
 p=subprocess.run([str(a) for a in cmd],capture_output=True,text=True,timeout=timeout)
 return p.returncode,(p.stdout+p.stderr).replace(str(app),'<tested App>')
action=sys.argv[1]
with tempfile.TemporaryDirectory(prefix='saytile-91-exact-app-') as td:
 temp=Path(td)
 if action=='microphone':
  code,log=execute([binary,'--data-directory',temp/'store','--device-probe'],45)
  print(log,flush=True)
  with sqlite3.connect((temp/'store/Saytile.sqlite').as_uri()+'?mode=ro',uri=True) as db: count=db.execute('select count(*) from recordings').fetchone()[0]
  lines=[s for s in log.splitlines() if 'DEVICE_PROBE' in s]
  import re
  fs=re.search(r' hardware_frames=(\d+)',log);ps=re.search(r' pinned_frames=(\d+)',log)
  save('hardware/packaged-microphone.json',dict(status='PASS' if code==0 and fs and ps and int(fs[1])>0 and int(ps[1])>0 and count==0 else ('BLOCKED' if 'NOT_RUN' in log else 'FAIL'),log=lines,recordings=count,wavs=len(list(temp.rglob('*.wav'))),exit=code))
 if action=='policy':
  checks={k:execute(args) for k,args in {'integrity':['codesign','--verify','--strict',app],'policy':['spctl','--status'],'assess':['spctl','--assess','--type','execute','-vv',app]}.items()}
  save('app/distribution-policy.json',dict(checks=checks))
 if action=='apple':
  fixture=json.loads((root/'evidence/no-api9/final/apple/fixture-identity.json').read_text())
  audio=Path(fixture['fixture_directory'])/'daily.aiff';assert h(audio)==fixture['generated_synthetic_audio'][audio.name]
  code,log=execute([binary,'--data-directory',temp/'store','--audio-probe',audio,'--prepare-speech'],150)
  (out/'app/apple.log').write_text(log)
  with sqlite3.connect((temp/'store/Saytile.sqlite').as_uri()+'?mode=ro',uri=True) as db:
   state=db.execute('select recognition_state,audio_state,is_recording from recordings').fetchall();text=db.execute('select text from revisions order by rowid desc limit 1').fetchone()
  wav=[(p.stat().st_size,h(p)) for p in temp.rglob('*.wav')]
  save('app/apple.json',dict(status='PASS' if code==0 and state==[('completed','available',0)] and text and text[0] and wav else 'FAIL',state=state,text=text,wavs=wav,fixture_sha256=h(audio)))
 if action=='upgrade':
  old=temp/'published-RC1.dmg';subprocess.run(['curl','-fLsS','--proxy','http://127.0.0.1:7895','--connect-timeout','12','--max-time','60','-o',old,'https://github.com/haohongfei2001-png/saytile/releases/download/v1.0.0-rc.1/Saytile-1.0.0-rc.1-arm64.dmg'],check=True)
  assert h(old)=='fb001a8ad0c107570acc6d263e590e49eb5bb9827d617e30c72cbaa4c247ed2a'
  with (out/'installation/driver.log').open('w') as f:
   subprocess.run(['python3','scripts/test-install-upgrade.py','--dmg',m['dmg_path'],'--previous-dmg',old,'--expected-source',m['source_revision'],'--expected-version',m['version'],'--expected-binary-sha256',m['binary_sha256'],'--output',out/'installation/upgrade.json'],stdout=f,stderr=subprocess.STDOUT,check=True)
