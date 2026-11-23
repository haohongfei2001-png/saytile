import json, subprocess, struct, wave, pathlib, hashlib
root=pathlib.Path(__file__).parent
app=pathlib.Path('/private/tmp/saytile-021-557-app/Saytile.app')
weights=pathlib.Path('/private/tmp/saytile-beta-021-20261123/.build/local-asr/weights/qwen-small/bc441bd1e4295c1f42d9879f056049a925b6e013')
results=[]
for r in json.loads((root/'failed-manifest.json').read_text()):
 path=root/(r['id']+'.wav')
 assert hashlib.sha256(path.read_bytes()).hexdigest()==r['audio_sha256']
 with wave.open(str(path)) as w:
  assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(1,2,16000)
  pcm=w.readframes(w.getnframes())
 payload=b''.join(struct.pack('<I',len(pcm[i:i+6400]))+pcm[i:i+6400] for i in range(0,len(pcm),6400))+struct.pack('<I',0)
 p=subprocess.run([str(app/'Contents/Helpers/SaytileModelWorker'),'qwen-small',str(weights),'12800'],input=payload,stdout=subprocess.PIPE,stderr=subprocess.PIPE,cwd=app/'Contents/Resources',timeout=90)
 events=[json.loads(line) for line in p.stdout.decode().splitlines() if line.startswith('{')]
 results.append({'source':r,'exit_code':p.returncode,'events':events,'stderr':p.stderr.decode()})
(root/'raw-worker.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
print([(r['source']['source'],r['exit_code'],r['events']) for r in results])
