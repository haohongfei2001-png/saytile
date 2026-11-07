from pathlib import Path
import subprocess,json,hashlib,datetime,tempfile,sys
out=Path('evidence/no-api9/machine-freeze')
ref=json.loads(Path('evidence/no-api9/final/local-vad-apple/identity.json').read_text())
h=lambda f:hashlib.sha256(Path(f).read_bytes()).hexdigest()
lib=Path(ref['build_argv'][ref['build_argv'].index('-L')+1])/'libSaytileKit.a'
assert h(lib)==ref['library_sha256']
with tempfile.TemporaryDirectory(prefix='saytile-route-check-') as tmp:
    temp=Path(tmp);src=out/'RouteProbe.swift';cmd=ref['build_argv'][:];cmd[cmd.index('-module-cache-path')+1]=str(temp/'cache');cmd[-3:]=[str(src),'-o',str(temp/'probe')]
    run=subprocess.run(cmd,capture_output=True,text=True)
    if run.returncode: print(run.stderr);sys.exit(run.returncode)
    p=subprocess.run([str(temp/'probe'),str(temp/'data')],capture_output=True,text=True,timeout=50);print(p.stdout,p.returncode)
    d=dict(source=ref['source_revision'],library_sha256=h(lib),probe_sha256=h(temp/'probe'),probe_source_sha256=h(src),utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),exit=p.returncode,output=p.stdout.splitlines(),wav_count=len(list(temp.rglob('*.wav'))))
    (out/'private-route.json').write_text(json.dumps(d,indent=2)+'\n')
