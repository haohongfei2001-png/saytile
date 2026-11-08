"""Two hours through the frozen worker. Reuse the existing Apple fixture, adding a periodic quiet interval."""
from pathlib import Path
import hashlib,json,subprocess,tempfile,time,sys,datetime
here=Path(__file__).resolve().parent
out=here/'active'
out.mkdir(exist_ok=False)
final=here.parent/'final'
ref=json.loads((final/'local-vad-apple/identity.json').read_text())
fixtures=json.loads((final/'apple/fixture-identity.json').read_text())
hashfile=lambda path:hashlib.sha256(Path(path).read_bytes()).hexdigest()
original=final/'local-vad-apple/LocalVADAppleProbe.swift'
assert hashfile(original)==ref['probe_source_sha256']
inputs=[Path(fixtures['fixture_directory'])/name for name in ('daily.aiff','tail.aiff')]
assert all(hashfile(f)==fixtures['generated_synthetic_audio'][f.name] for f in inputs)
with tempfile.TemporaryDirectory(prefix='saytile-active-soak-') as raw:
    temp=Path(raw)
    code=original.read_text()
    replacements={
       'for i in stride(from:0,to:signal.count,by:step)':'''let period = Int(first.rate) * 180
        let total = period * 40
        signal.append(contentsOf: repeatElement(Float.zero, count: period - signal.count))
        for i in stride(from:0,to:total,by:step)''',
       'let count=min(step,signal.count-i)':'let count=min(step,total-i)',
       'advanced(by:i)':'advanced(by:i % period)',
       '(i/step).isMultiple(of:5)':'(i/step).isMultiple(of:50)',
       'totalInputFrames:signal.count':'totalInputFrames:total',
       'let schedule=[':'let schedule=["cycleSeconds":180.0, "cycleCount":40.0, ',
       'store.listRecordings()':'store.listRecordings(limit:200)',
    }
    for old,new in replacements.items():
        assert old in code,old
        code=code.replace(old,new)
    src=out/'PacedCaptureProbe.swift';src.write_text(code)
    argv=ref['build_argv'][:];argv[argv.index('-module-cache-path')+1]=str(temp/'cache');argv[-3:]=[str(src),'-o',str(temp/'probe')]
    lib=Path(argv[argv.index('-L')+1])/'libSaytileKit.a'
    assert hashfile(lib)==ref['library_sha256']
    subprocess.run(argv,check=True)
    meta={'source':ref['source_revision'],'tree':ref['tree'],'library_sha256':hashfile(lib),'probe_sha256':hashfile(temp/'probe'),'probe_source_sha256':hashfile(src),'fixture_hashes':{f.name:hashfile(f) for f in inputs},'source_probe':str(original.relative_to(here.parents[2])),'duration_seconds':7200,'cycle_seconds':180,'utterances_expected':80,'start_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    (out/'start.json').write_text(json.dumps(meta,indent=2)+'\n')
    report=temp/'raw.json'
    with (temp/'diagnostic.log').open('w') as stream:
        proc=subprocess.Popen([str(temp/'probe'),*map(str,inputs),str(temp/'store'),str(report)],stdout=stream,stderr=subprocess.STDOUT)
        start=time.monotonic()
        try:
            with (out/'samples.jsonl').open('x',buffering=1) as samples:
                while proc.poll() is None:
                    ps=subprocess.run(['ps','-p',str(proc.pid),'-o','rss=,time='],text=True,capture_output=True)
                    if ps.returncode==0:print(json.dumps(dict(seconds=round(time.monotonic()-start,3),status=ps.stdout.split())),file=samples)
                    try:proc.wait(timeout=60)
                    except subprocess.TimeoutExpired:pass
                    if time.monotonic()-start>7500:raise TimeoutError('capture worker did not finish')
        finally:
            if proc.poll() is None:proc.terminate();proc.wait(timeout=10)
    receipt={**meta,'exit':proc.returncode,'elapsed':time.monotonic()-start,'unchanged':hashfile(lib)==ref['library_sha256']}
    if report.exists():
        d=json.loads(report.read_text());records=d['records']
        receipt.update(drops=d['ringDropped'],failures=d['workerErrors'],records=len(records),completed=sum(r['row']['state']=='completed' for r in records),all_wavs_valid=all(r['chunks'] and all(c['valid'] for c in r['chunks']) for r in records),all_final_texts=all(r.get('finalRevision') for r in records),cloud=d['usesCloud'],microphone=d['microphoneOpened'])
        receipt['status']='PASS' if proc.returncode==0 and receipt['unchanged'] and not d['ringDropped'] and not d['workerErrors'] and receipt['records']==receipt['completed']==80 and receipt['all_wavs_valid'] and receipt['all_final_texts'] and not d['usesCloud'] and not d['microphoneOpened'] else 'FAIL'
        receipt['raw_sha256']=hashfile(report)
        # Preserve raw candidates and text for synthetic utterances only.
        import gzip
        (out/'observations.json.gz').write_bytes(gzip.compress(report.read_bytes(),mtime=0))
    else:receipt.update(status='BLOCKED',reason='probe produced no final report')
    (out/'result.json').write_text(json.dumps(receipt,indent=2)+'\n')
