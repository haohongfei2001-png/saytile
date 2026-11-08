"""Finite follow-through for this measurement only. Publish observed receipts without touching main."""
import subprocess,tempfile,time,json,datetime,sys,os
from pathlib import Path
source='0a0cdecab8eb099e1dc3bb21b4c15ba5c30c93f0'
root=Path(__file__).resolve().parents[4]
base=root/'evidence/no-api9.1'
branch='refs/heads/engine/single-transcript-integrated-20261107'
iv=json.loads((base/'sustained/soak/interval.json').read_text())
active=json.loads((base/'sustained/active/start.json').read_text())
assert iv['source']==active['source']==source
def git(cwd,*args):
    cp=subprocess.run(['git','-c','http.proxy=http://127.0.0.1:7895','-c','http.version=HTTP/1.1',*map(str,args)],check=True,cwd=cwd,stdout=subprocess.PIPE,text=True,timeout=180)
    return cp.stdout.strip()
def run(args,cwd):
    subprocess.run(list(map(str,args)),check=True,cwd=cwd,timeout=180)
def publish(phase):
    snap=base/'snapshots'/phase
    if not (snap/'machine.json').exists():run([sys.executable,base/'report.py',phase],root)
    with tempfile.TemporaryDirectory(prefix='saytile-91-evidence-publish-') as td:
        target=Path(td)/'repo'
        git(root,'fetch','origin',branch);git(root,'worktree','add','--quiet','--detach',target,'FETCH_HEAD')
        try:
            if git(target,'diff','--name-only',source,'HEAD','--','Sources','tests','scripts','packaging','Package.swift'):
                # Do not label an incoming unrelated runtime with this candidate's result.
                raise RuntimeError('Product source advanced. Fixed-source receipts remain local for separate publication.')
            run([sys.executable,base/'sustained/ops/copy-evidence.py'],target);run([sys.executable,base/'sustained/ops/publication-docs.py',phase],target)
            harness='.github/workflows/no-api9-machine-foreground.yml'
            code=git(target,'show','7b82d60ca4b959925590e01741cbe8be3ae3b21e:'+harness)
            assert 'ref: '+source in code and "branches: ['codex/no-api9-ax-host-check']" in code
            (target/harness).write_text(code+'\n')
            git(target,'add',harness)
            git(target,'add','--','README.md','docs/00-DELIVERY-STATUS.md','docs/V1-NO-API-DELIVERY.md','docs/V1-DEV-STATUS.md','docs/V1-TEST-RESULTS.md','docs/V1-USER-ACTIONS.md','evidence/no-api9.1','deliverables/no-api.9.1')
            run([sys.executable,'scripts/update-manifest.py'],target);git(target,'add','SHA256SUMS.txt');git(target,'diff','--cached','--check');run([sys.executable,'scripts/check_integrity.py'],target)
            changes=git(target,'diff','--cached','--name-only')
            assert changes and all(p=='SHA256SUMS.txt' or p=='README.md' or p=='.github/workflows/no-api9-machine-foreground.yml' or p.startswith(('docs/','evidence/no-api9.1/','deliverables/no-api.9.1/')) for p in changes.splitlines())
            git(target,'commit','--quiet','-m',f'Archive {phase} machine results for the tested device-repair candidate');sha=git(target,'rev-parse','HEAD')
            git(target,'push','origin','HEAD:'+branch)
            print(phase,sha,flush=True)
            # Verify the durable public ref instead of resubmitting an uncertain push.
            remote = git(target,'ls-remote','origin',branch).split()[0]
            if remote!=sha:
                git(target,'fetch','origin',branch)
                run(['git','merge-base','--is-ancestor',sha,'FETCH_HEAD'],target)
            Path('/tmp/saytile-91-published-'+phase+'.json').write_text(json.dumps({'source':source,'commit':sha,'phase':phase,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat()})+'\n')
        finally:
            git(root,'worktree','remove',target)
def wait_for(relative,deadline):
    f=base/relative
    while not f.is_file() and time.time()<deadline:time.sleep(min(60,max(.1,deadline-time.time())))
    return f.is_file()
def checkpoint(phase):
    try:publish(phase);return
    except Exception as first:
        try:
            snap=base/'snapshots'/phase/'machine.json'
            sha=git(root,'fetch','origin',branch)
            import hashlib
            expected=hashlib.sha256(snap.read_bytes()).hexdigest()
            rel=str(snap.relative_to(root))
            obj=subprocess.run(['git','show','FETCH_HEAD:'+rel],cwd=root,capture_output=True)
            if obj.returncode==0 and hashlib.sha256(obj.stdout).hexdigest()==expected:
                print(phase,'previous push confirmed on remote',flush=True);return
            if not isinstance(first,subprocess.SubprocessError):raise first
            time.sleep(25)
            publish(phase);return
        except Exception as last:
            Path('/tmp/saytile-91-publication-'+phase+'-error.txt').write_text(str(last)+'\n')
            print(phase,'publication requires attention:',str(last),flush=True)
if __name__=='__main__':
    if len(sys.argv)==2:
        if sys.argv[1] not in ('public','2h','repeat-start','2h-verified','72h','interrupted','repeat-interrupted'):raise SystemExit('unknown phase')
        checkpoint(sys.argv[1]);raise SystemExit
    due=datetime.datetime.fromisoformat(iv['due_utc']).timestamp()
    start=datetime.datetime.fromisoformat(active['start_utc']).timestamp()
    if not (base/'snapshots/2h/machine.json').exists():
        wait_for('sustained/active/result.json',start+9000)
        checkpoint('2h')
    retry=base/'sustained/active-repeat/start.json'
    if retry.is_file() and not (base/'snapshots/2h-verified/machine.json').exists():
        issued=datetime.datetime.fromisoformat(json.loads(retry.read_text())['start_utc']).timestamp()
        wait_for('sustained/active-repeat/result.json',issued+9000)
        checkpoint('2h-verified')
    terminal=wait_for('sustained/soak/result.json',due+600)
    outcome=json.loads((base/'sustained/soak/result.json').read_text())['status'] if terminal else 'BLOCKED'
    checkpoint('72h' if outcome=='PASS' else 'interrupted')
