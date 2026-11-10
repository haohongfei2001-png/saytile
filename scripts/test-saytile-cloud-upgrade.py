"""Exercise both officially signed schema-v6 apps in a disposable Applications folder."""
import argparse, json, re, runpy, shutil, sqlite3, tempfile
from pathlib import Path
base=runpy.run_path(str(Path(__file__).with_name('test-rc2-timeline-upgrade.py')))
globals().update({k:base[k] for k in ('ROOT','run','sha','mount','info','requirement','probe','smoke','seed_media','snapshot')})
p=argparse.ArgumentParser()
for n in ('baseline','candidate','output','scratch'): p.add_argument('--'+n,type=Path,required=True)
p.add_argument('--local-weights',type=Path,help='isolated verified sherpa snapshot for the local candidate')
a=p.parse_args()
expected_baseline = ('dcb9d9b93241653ce192eaeb57662e8f14fd6b3cc11deac9e42389bab6978ed1' if a.local_weights else
                     '022a78a5428f5fe806f2d6fa3dbcffed401089e1fe80ec7d36a220496f77acab')
assert sha(a.baseline) == expected_baseline
identity=re.findall(r'\b([0-9A-F]{40}) "Developer ID Application:',run('security','find-identity','-v','-p','codesigning').stdout)
assert len(identity)==1
def state(d):
    with sqlite3.connect(d/'Saytile.sqlite') as db: timeline=db.execute('select * from transcript_timeline order by position').fetchall()
    return snapshot(d),timeline
with tempfile.TemporaryDirectory(prefix='saytile-commercial-upgrade-') as raw:
    tmp=Path(raw); root=tmp/'Applications'/'Saytile.app';root.parent.mkdir();data=tmp/'fixture';data.mkdir()
    with mount(a.baseline.resolve(),tmp/'before') as old,mount(a.candidate.resolve(),tmp/'after') as new:
        assert requirement(old)==requirement(new);assert info(old)['CFBundleIdentifier']==info(new)['CFBundleIdentifier']=='app.saytile.mac'
        assert int(info(old)['CFBundleVersion'])<int(info(new)['CFBundleVersion']) and not info(new)['SaytileSourceDirty']
        src=tmp/'oldsrc';src.mkdir();archive=tmp/'old.tar';oldsha=info(old)['SaytileSourceRevision']
        run('git','-C',ROOT,'archive',oldsha,'-o',archive,'Package.swift','Sources','tests/SaytileKitTests');run('tar','-xf',archive,'-C',src)
        oldprobe=tmp/'seed';newprobe=tmp/'read';fixture=tmp/'accounts.json'
        probe(src,tmp/'old-build',oldprobe,identity[0]);probe(ROOT,a.scratch,newprobe,identity[0])
        try:
            run('ditto',old,root);smoke(root,data);run(oldprobe,'seed',data,fixture);seed_media(data,json.loads(fixture.read_text()));smoke(root,data)
            if a.local_weights:
                manifest=json.loads((ROOT/'Sources/SaytileKit/Resources/LocalASR/sherpa.json').read_bytes())
                destination=data/'LocalModels'/'sherpa'/manifest['revision']
                destination.parent.mkdir(parents=True)
                run('cp','-cR',a.local_weights/'sherpa'/manifest['revision'],destination)
            reference=state(data);assert reference[0][0]==6 and len(reference[1])==2
            for app,binary in ((new,newprobe),(old,oldprobe)):
                shutil.rmtree(root);run('ditto',app,root);smoke(root,data);assert state(data)==reference;run(binary,'verify',data,fixture)
                if a.local_weights:
                    assert all(sha(destination/f['path'])==f['sha256'] for f in manifest['files'])
            receipt=dict(verifiedModelBytesPreserved=sum(f['bytes'] for f in manifest['files']) if a.local_weights else None,status='PASS',scope='disposable signed app replacement and same-schema rollback',baseline=oldsha,candidate=info(new)['SaytileSourceRevision'],candidateDMG=sha(a.candidate),schema=6,timelineRows=len(reference[1]),audioFiles=len(reference[0][2]),randomBYOKCredentialsPreserved=True,realUserDataTouched=False)
        finally:
            if fixture.exists():run(oldprobe,'cleanup',data,fixture)
a.output.write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt))
