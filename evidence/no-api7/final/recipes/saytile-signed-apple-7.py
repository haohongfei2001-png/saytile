from pathlib import Path
import json,sqlite3,tempfile,hashlib,subprocess as sp
root=Path.cwd();out=root/'evidence/no-api7/final/apple';meta=json.loads((out.parent/'package-identity.json').read_text())
bin=Path(meta['app_path'])/'Contents/MacOS/Saytile';hash=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inp=json.loads((out/'fixture-identity.json').read_text());fixture=Path(inp['fixture_directory'])/'daily.aiff'
assert hash(fixture)==inp['generated_synthetic_audio'][fixture.name] and hash(bin)==meta['binary_sha256']
runs=[]
with tempfile.TemporaryDirectory(prefix='saytile-signed-apple-fixture-') as tmp:
 for attempt in range(2):
  data=Path(tmp)/('data-'+str(attempt));cmd=[str(bin),'--data-directory',str(data),'--audio-probe',str(fixture)]
  if attempt: cmd.append('--prepare-speech')
  r=sp.run(cmd,capture_output=True,text=True,timeout=180)
  raw=r.stdout+r.stderr
  (out/('signed-app-'+str(attempt)+'.log')).write_text(raw)
  with sqlite3.connect(('file:'+str(data/'Saytile.sqlite')+'?mode=ro'),uri=True) as db:
   rec=db.execute('select recognition_state,audio_state,is_recording from recordings').fetchall()
   rev=db.execute('select text from revisions order by rowid desc limit 1').fetchone()
   audio=[(p.stat().st_size,hash(p)) for p in (data/'Audio').rglob('*.wav')]
   checks={'exit':r.returncode,'rows':rec,'latest_text':None if rev is None else rev[0], 'saved_wavs':audio,'resource_prepare_requested':bool(attempt),'scope':'Bundled signed executable, file-fed synthetic audio, local Apple only. No microphone or cloud provider.'}
   runs.append(checks)
  if r.returncode==0 and 'SPEECH_RESULT completed' in raw and rec==[('completed','available',0)] and rev and rev[0] and audio: break
  # Do not turn generic failure into an automatic retry.
  if attempt or not ('需要下载 Apple 中文识别资源' in raw or '下载中文识别资源' in raw):break
assert hash(bin)==meta['binary_sha256'] and hash(fixture)==inp['generated_synthetic_audio'][fixture.name]
status=any(row['rows']==[('completed','available',0)] and row['latest_text'] and row['saved_wavs'] for row in runs)
receipt={'passed':status,'runtime':meta['source_revision'],'binary_sha256':hash(bin),'synthesized_fixture':fixture.name,'fixture_sha256':hash(fixture),'attempts':runs}
(out/'signed-app.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n');print(json.dumps(receipt,ensure_ascii=False))
raise SystemExit(0 if status else 1)
