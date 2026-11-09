"""Exercise both officially signed schema-v6 apps in a disposable Applications folder."""
import argparse, json, re, runpy, shutil, sqlite3, tempfile
from pathlib import Path
base=runpy.run_path(str(Path(__file__).with_name('test-rc2-timeline-upgrade.py')))
globals().update({k:base[k] for k in ('ROOT','run','sha','mount','info','requirement','probe','smoke','seed_media','snapshot')})
p=argparse.ArgumentParser()
for n in ('baseline','candidate','output','scratch'): p.add_argument('--'+n,type=Path,required=True)
a=p.parse_args()
assert sha(a.baseline)=='022a78a5428f5fe806f2d6fa3dbcffed401089e1fe80ec7d36a220496f77acab'
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
            reference=state(data);assert reference[0][0]==6 and len(reference[1])==2
            for app,binary in ((new,newprobe),(old,oldprobe)):
                shutil.rmtree(root);run('ditto',app,root);smoke(root,data);assert state(data)==reference;run(binary,'verify',data,fixture)
            receipt=dict(status='PASS',scope='disposable signed app replacement and same-schema rollback',baseline=oldsha,candidate=info(new)['SaytileSourceRevision'],candidateDMG=sha(a.candidate),schema=6,timelineRows=len(reference[1]),audioFiles=len(reference[0][2]),randomBYOKCredentialsPreserved=True,realUserDataTouched=False)
        finally:
            if fixture.exists():run(oldprobe,'cleanup',data,fixture)
a.output.write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt))
