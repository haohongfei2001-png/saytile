"""Public fixtures only. Diagnostic gain/context are NOT product preprocessing."""
import array, hashlib, json, math, pathlib, struct, subprocess, wave
root = pathlib.Path(__file__).resolve().parents[3]
out = pathlib.Path(__file__).parent
original = pathlib.Path('/private/tmp/saytile-021-five-recovery-v2')
app = pathlib.Path('/private/tmp/saytile-021-563-app/Saytile.app')
weights = root/'.build/local-asr/weights/qwen-small/bc441bd1e4295c1f42d9879f056049a925b6e013'
temporary = pathlib.Path('/private/tmp/saytile-closure-empty-diagnostic'); temporary.mkdir(exist_ok=True)
rows = json.loads((out/'alignment.json').read_text())
results = []
def read(path):
    with wave.open(str(path)) as w:
        assert (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (16000,1,2)
        return w.readframes(w.getnframes())
def recognize(pcm):
    payload = b''.join(struct.pack('<I', len(pcm[i:i+6400]))+pcm[i:i+6400] for i in range(0,len(pcm),6400))+struct.pack('<I',0)
    p = subprocess.run([str(app/'Contents/Helpers/SaytileModelWorker'),'qwen-small',str(weights),'12800'],
        input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=app/'Contents/Resources', timeout=90)
    return {'exit':p.returncode,'events':[json.loads(x) for x in p.stdout.splitlines() if x.startswith(b'{')], 'stderr':p.stderr.decode()}
for r in rows:
    pcm = read(original/(r['id']+'.wav')); whole = read(root/'.build/mandarin/wav'/(r['source']+'.wav'))
    assert whole[2*r['source_offset_frames']:2*r['source_offset_frames']+len(pcm)] == pcm
    samples=array.array('h',pcm); rms=math.sqrt(sum(v*v for v in samples)/len(samples)); peak=max(map(abs,samples))
    gain=min(10**(-26/20)*32768/max(rms,1), 10**(-1/20)*32768/max(peak,1))
    gained=array.array('h',(round(v*gain) for v in samples)).tobytes()
    lo=max(0,r['source_offset_frames']-32000);hi=min(len(whole)//2,r['source_offset_frames']+len(samples)+32000)
    variants={'whole':whole,'original':pcm,'normalized-diagnostic-only':gained,'context-diagnostic-only':whole[lo*2:hi*2]}
    result={'id':r['source'],'original_wav_sha256':r['audio_sha256'],'gain_db':20*math.log10(gain),
            'context_frames':[lo,hi], 'variants':{}}
    for name, data in variants.items():
        path=temporary/(r['source']+'-'+name+'.wav')
        with wave.open(str(path),'wb') as w: w.setparams((1,2,16000,0,'NONE','not compressed'));w.writeframes(data)
        value=recognize(data);value.update(pcm_sha256=hashlib.sha256(data).hexdigest(),frames=len(data)//2,wav_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        result['variants'][name]=value
        print(r['source'],name,[(e['kind'],e.get('text')) for e in value['events'] if e['kind']=='final'],flush=True)
    results.append(result)
    (out/'qwen-diagnostic.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
