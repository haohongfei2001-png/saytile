"""Replay the two approved synthetic phrases in real time for two hours on the specified source."""
import argparse
import datetime
import gzip
import hashlib
import json
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--fixtures', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def git(*command):
    return subprocess.check_output(['git', *command], cwd=root, text=True).strip()
def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(name, data):
    (out/name).write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
assert git('rev-parse','HEAD') == args.source
assert not git('diff','--name-only',args.source,'--','Sources','Package.swift','packaging','tests')
source = root/'evidence/no-api9.1/sustained/active/PacedCaptureProbe.swift'
manifest = json.loads((root/'evidence/no-api9/final/apple/fixture-identity.json').read_text())
inputs = [args.fixtures/name for name in ('daily.aiff','tail.aiff')]
hashes = {p.name:digest(p) for p in inputs}
assert all(hashes[name] == manifest['generated_synthetic_audio'][name] for name in hashes)
with tempfile.TemporaryDirectory(prefix='saytile-seal-speech-') as td:
    work = Path(td)
    build = ['swift','build','--product','SaytileKit','--scratch-path',str(work/'build'),'-Xswiftc','-enable-testing']
    with (out/'build.log').open('w') as log:
        subprocess.run(build, cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
        bin_dir = Path(subprocess.check_output([*build,'--show-bin-path'],cwd=root,text=True).strip())
        module = bin_dir/'../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap'
        if not module.is_file(): module = bin_dir/'CAudio.build/module.modulemap'
        lib = bin_dir/'libSaytileKit.a'
        exe = work/'paced'
        subprocess.run(['swiftc','-parse-as-library','-swift-version','6','-I',root/'Sources/CSQLite',
                        '-I',bin_dir,'-I',bin_dir/'Modules','-Xcc','-fmodule-map-file='+str(module.resolve()),
                        '-L',bin_dir,'-lSaytileKit','-lc++',source,'-o',exe],cwd=root,stdout=log,stderr=subprocess.STDOUT,check=True)
    tested = [source,lib,exe,*inputs]
    fingerprint = [digest(p) for p in tested]
    meta = dict(source=args.source, tree=git('rev-parse',args.source+'^{tree}'), start_utc=now(),
                binary_sha256=fingerprint[2], library_sha256=fingerprint[1], probe_source_sha256=fingerprint[0], fixtures=hashes)
    save('start.json',meta)
    raw = work/'speech.json'
    start = time.monotonic()
    with (out/'runtime.log').open('w') as log, (out/'samples.jsonl').open('w',buffering=1) as samples:
        proc = subprocess.Popen([exe,*inputs,work/'store',raw],stdout=log,stderr=subprocess.STDOUT)
        try:
            while proc.poll() is None:
                usage=subprocess.run(['ps','-p',str(proc.pid),'-o','rss=,time='],capture_output=True,text=True)
                if usage.returncode==0: print(json.dumps(dict(seconds=time.monotonic()-start,rss_cpu=usage.stdout.split())),file=samples)
                try: proc.wait(timeout=60)
                except subprocess.TimeoutExpired: pass
                if time.monotonic()-start>7600: raise TimeoutError('Timed out waiting for speech worker')
        finally:
            if proc.poll() is None: proc.terminate();proc.wait(timeout=20)
    elapsed = time.monotonic()-start
    result = dict(**meta, exit=proc.returncode, elapsed_seconds=elapsed, end_utc=now(),
                  inputs_intact=[digest(p) for p in tested]==fingerprint, status='FAIL')
    if raw.is_file():
        d=json.loads(raw.read_text()); records=d['records']
        with raw.open('rb') as src, gzip.open(out/'observations.json.gz','wb') as dst:
            import shutil
            shutil.copyfileobj(src,dst)
        previews={s['row']['id'] for s in d['observations'] if s['row']['open'] and s['row']['text']}
        result.update(records=len(records),completed=sum(r['row']['state']=='completed' and bool(r.get('finalRevision')) for r in records),
                      records_with_live_text=len(previews),valid_wavs=sum(bool(r['chunks']) and all(c['valid'] for c in r['chunks']) for r in records),
                      ring_drops=d['ringDropped'],worker_errors=d['workerErrors'],uses_cloud=d['usesCloud'],opened_microphone=d['microphoneOpened'])
        if (elapsed>=7200 and proc.returncode==0 and result['inputs_intact'] and
            result['completed']==result['valid_wavs']==len(records)==len(previews)==80 and
            not any((d['ringDropped'],d['workerErrors'],d['usesCloud'],d['microphoneOpened']))):result['status']='PASS'
    save('result.json',result)
    print(result['status'],result.get('completed'),elapsed)
    raise SystemExit(result['status']!='PASS')
