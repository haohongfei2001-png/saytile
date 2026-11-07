#!/usr/bin/env python3
"""Compile the frozen production integration probe and run once on two already-generated fixtures."""
import hashlib, json, os, sqlite3, subprocess, sys, tempfile, time, wave
from pathlib import Path
from datetime import datetime, timezone

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
SHA="dc26fe3c59ba55994d29e99ada8d2f0b49ad9886"
TREE="f138f6733a642a2e53da22b3647aaf5744cb308b"
hashfile=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
def dump(f,d):f.write_text(json.dumps(d,ensure_ascii=False,sort_keys=True,indent=2)+"\n")
def head():
    return subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip()
def tree():
    return subprocess.check_output(["git","rev-parse","HEAD^{tree}"],cwd=ROOT,text=True).strip()

if (head(),tree())!=(SHA,TREE):
    sys.exit("Use this runner on the frozen no-api.9 revision.")
if subprocess.check_output(["git","diff","--name-only","HEAD","--","Sources","tests","scripts","packaging","Package.swift"],cwd=ROOT,text=True).strip():
    sys.exit("Tracked runtime source differs from the frozen revision.")
if (HERE/"run.log").exists():
    sys.exit("Prior execution exists; preserve it, do not replay into this evidence directory.")

apple=json.loads((HERE.parent/"apple"/"receipt.json").read_text())
native=json.loads((HERE.parent/"protocol"/"run-after.json").read_text())
assert apple['runtime']==SHA and native['head']==SHA and native["result"]=="PASS"
inputs=[Path(apple['fixture_directory'])/(name+'.aiff') for name in ('daily','tail')]
input_before={f.name:hashfile(f) for f in inputs}
assert all(apple["generated_synthetic_audio"][name]==h for name,h in input_before.items())
scratch=Path(tempfile.mkdtemp(prefix="saytile-vad-apple-"+SHA[:12]+"-"))
lib=next(Path(native['scratch']).rglob('libSaytileKit.a'));bindir=lib.parent
modulemap=(bindir/'../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap').resolve()
if not modulemap.exists():modulemap=next(Path(native['scratch']).rglob('CAudio.modulemap'))
source=HERE/'LocalVADAppleProbe.swift'
exe=scratch/'probe'
flags=['swiftc','-swift-version','6','-parse-as-library','-module-cache-path',str(scratch/'module-cache'),'-I',str(bindir),'-I',str(bindir/'Modules'),'-I',str(ROOT/'Sources/CSQLite'),'-Xcc','-fmodule-map-file='+str(modulemap),'-L',str(bindir),'-lSaytileKit','-lc++',str(source),'-o',str(exe)]
with (HERE/'build.log').open('w')as f:res=subprocess.run(flags,stdout=f,stderr=subprocess.STDOUT,cwd=ROOT,timeout=60)
if res.returncode:print((HERE/'build.log').read_text()[-2500:]);sys.exit(res.returncode)
store=scratch/'owned-store';report=HERE/'raw-report.json';command=[str(exe),*map(str,inputs),str(store),str(report)]
metadata={'source_revision':SHA,'tree':TREE,'scratch':str(scratch),'store_directory':str(store),'input_before':input_before,
          'probe_sha256':hashfile(exe),'library_sha256':hashfile(lib),'probe_source_sha256':hashfile(source),'build_argv':flags,'probe_argv':command,
          'capture_input':'Only generated MandarinCorpus daily and tail AIFF. Initial 0.25 s silence, 1.6 s gap, 1.6 s tail. Float PCM from AVAudioFile is paced by absolute 20 ms deadlines into CAudio ring. No microphone or audio output.',
          'recognition':'Default CaptureWorker with no recognition factory argument. Uses production VoiceSegmenter, PCMJournal, actual AppleSpeechService/Apple session and durable Store.',
          'started':datetime.now(timezone.utc).isoformat()}
dump(HERE/'identity.json',metadata)
t0=time.monotonic()
try:
    with (HERE/'run.log').open('x')as f:res=subprocess.run(command,stdout=f,stderr=subprocess.STDOUT,env=dict(os.environ,DYLD_LIBRARY_PATH=str(bindir)),timeout=115)
    exitcode=res.returncode
except subprocess.TimeoutExpired:
    exitcode=124
metadata.update(wall_seconds=time.monotonic()-t0,exit=exitcode,finished=datetime.now(timezone.utc).isoformat(),
                input_after={f.name:hashfile(f)for f in inputs},source_unchanged=(head(),tree())==(SHA,TREE),probe_hash_unchanged=hashfile(exe)==metadata['probe_sha256'],
                library_hash_unchanged=hashfile(lib)==metadata['library_sha256'])
dump(HERE/'identity.json',metadata)
if exitcode or not report.exists():
    print((HERE/'run.log').read_text()[-1050:]);sys.exit(exitcode or 1)
raw=json.loads(report.read_text());db=sqlite3.connect(f"file:{store/'Saytile.sqlite'}?mode=ro",uri=True)
count=lambda table:db.execute('SELECT COUNT(*) FROM '+table).fetchone()[0]
records=raw['records'];observed=raw['observations']
checks={'two_distinct_records':len(records)==2 and len({r['row']['id']for r in records})==2,
        'two_vad_onsets_and_offsets':sum(t['speaking'] for t in raw['transitions'])==2 and len(raw['transitions'])>=4 and not raw['transitions'][-1]['speaking'],
        'no_capture_errors':not raw['workerErrors'],'no_ring_drops':raw['ringDropped']==0,
        'default_cloud_disabled':not raw['usesCloud'],'no_microphone':not raw['microphoneOpened'],
        'no_upload_grants':count('recording_cloud_authorizations')==0,'sqlite_ok':db.execute('PRAGMA integrity_check').fetchone()[0]=='ok',
        'known_synthetic_inputs_unchanged':input_before==metadata['input_after']}
db.close()
details=[]
for i,r in enumerate(records):
    rid=r['row']['id'];cs=r['candidates']
    snapshots=[o for o in observed if o['row']['id']==rid];partial=[o for o in snapshots if o['row']['text']and o['row']['open']]
    files=[]
    for chunk in r['chunks']:
        wav=next((store/'Audio').rglob(Path(chunk['path']).name),None)
        if wav is None:wav=next(store.rglob(Path(chunk['path']).name))
        with wave.open(str(wav)) as wf:
            rec={'relative_path':chunk['path'],'frames':wf.getnframes(),'rate_hz':wf.getframerate(),'sample_bytes':wf.getsampwidth(),'channels':wf.getnchannels(),'sha256':hashfile(wav),'bytes':wav.stat().st_size}
        files.append(rec)
    checks[f'{i+1}_valid_saved_wav']=bool(files)and all(c['valid']for c in r['chunks']) and all(w['rate_hz']==16000 and w['sample_bytes']==2 and w['channels']==1 and w['frames']>0 for w in files)
    checks[f'{i+1}_visible_partial_while_recording']=bool(partial)
    checks[f'{i+1}_real_apple_progressive_evidence']=bool(cs) and {c['run']['provider']for c in cs}=={'apple-speech-analyzer'} and any(c['text']and not c['isComplete']for c in cs)
    checks[f'{i+1}_real_apple_final']=bool(r['finalRevision']) and r['finalRevision']==r['row']['text'] and r['row']['state']=='completed' and 'final' in r['revisionOrigins'] and any(c['isComplete']for c in cs)
    details.append({'recording_id':rid,'candidate_count':len(cs),'observed_while_open_texts':len(partial),'first_nonempty_open_s':partial[0]['elapsed'] if partial else None,
                    'final_s':next((o['elapsed']for o in snapshots if o['row']['state']=='completed'),None),'final_text':r['finalRevision'],'last_error':r.get('lastError'),'chunks':files})
checks['distinct_text_on_correct_recordings'] = len(details)==2 and '开会' in (details[0]['final_text'] or '') and '收音' in (details[1]['final_text'] or '')
s={'status':'PASS' if all(checks.values()) else 'OBSERVED_INCOMPLETE','scope':'Short same-worker synthetic local engineering integration. Not a natural-speech accuracy benchmark, model comparison, physical input or cloud proof.','source_revision':SHA,'tree':TREE,'checks':checks,'records':details,'source_sample_rate':raw['sampleRate'],'feed_wall_seconds':raw['feedActualSeconds'],'input_frames':raw['totalInputFrames'],'raw_report_sha256':hashfile(report),'recognition_asset_setup_calls':raw['prepareCalls'],'recognition_asset_status_before':raw['initialAssetStatus'],'recognition_asset_status_during':raw['finalAssetStatus']}
dump(HERE/'summary.json',s)
print(s['status'],checks,flush=True)
sys.exit(0 if all(checks.values()) else 2)
