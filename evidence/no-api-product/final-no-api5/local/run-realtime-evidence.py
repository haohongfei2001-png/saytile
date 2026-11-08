#!/usr/bin/env python3
"""Bind one actual 1800-second synthetic run to frozen source; observe only its owned process/data."""
import hashlib,json,pathlib,re,sqlite3,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[4]
OUT=pathlib.Path(__file__).resolve().parent
EXPECTED='702a24b9767826275f650c70f7e118365601a2a8'
SCRATCH=pathlib.Path('/tmp/saytile-final-702a24b9-realtime')
FIXTURE=pathlib.Path('/Users/hhf/.codex/worktrees/saytile-approved-ui/evidence/no-api-product/intermediate-d4b9dbe/local/realtime-synthetic-source.aiff')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def source():
    files=[p for d in ['Sources','scripts','tests','packaging'] for p in (ROOT/d).rglob('*') if p.is_file() and '.DS_Store' not in p.name]+[ROOT/'Package.swift']
    return {str(p.relative_to(ROOT)):sha(p) for p in sorted(files)}
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
assert head==EXPECTED
before={'expected_source_revision':EXPECTED,'head_before':head,'tree_before':subprocess.check_output(['git','rev-parse','HEAD^{tree}'],cwd=ROOT,text=True).strip(),'unix_started':time.time(),'source_sha256':source(),'input_sha256':sha(FIXTURE)}
(OUT/'source-before.json').write_text(json.dumps(before,indent=2)+'\n')
import os
env=dict(os.environ,SAYTILE_AUDIO_SCRATCH=str(SCRATCH))
with (OUT/'realtime-run.log').open('w') as log:
    runner=subprocess.Popen(['bash','scripts/test-audio-realtime.sh',str(FIXTURE),'1800'],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    pid=None;data=None;observed=None;probe_identity=None
    deadline=time.monotonic()+2400
    while runner.poll() is None:
        if time.monotonic()>deadline:
            raise TimeoutError('Run monitor timeout; do not infer successful completion or kill unrelated process')
        if pid is None:
            found=subprocess.run(['pgrep','-f','^'+re.escape(str(SCRATCH/'realtime-probe'))+' '],capture_output=True,text=True)
            ids=[int(x) for x in found.stdout.split()]
            if len(ids)==1:
                pid=ids[0];observed=time.monotonic()
                probe_identity={'pid':pid,'binary':str(SCRATCH/'realtime-probe'),'binary_sha256':sha(SCRATCH/'realtime-probe'),'unix_observed':time.time()}
                (OUT/'realtime-probe-identity.json').write_text(json.dumps(probe_identity,indent=2)+'\n')
        if data is None:
            matches=re.findall(r'^Data directory: (/.+)$',(OUT/'realtime-run.log').read_text(),re.M)
            if matches: data=pathlib.Path(matches[-1]);assert str(data).startswith('/tmp/saytile-rc-realtime-data.')
        if pid is not None:
            ps=subprocess.run(['ps','-p',str(pid),'-o','pid=,etime=,rss=,%cpu=,command='],capture_output=True,text=True)
            row={'unix':time.time(),'elapsed_observation_seconds':time.monotonic()-observed,'ps':ps.stdout.strip()}
            with (OUT/'realtime-resources.jsonl').open('a') as f:f.write(json.dumps(row)+'\n')
            if data and (data/'Saytile.sqlite').exists():
                try:
                    db=sqlite3.connect('file:'+str(data/'Saytile.sqlite')+'?mode=ro',uri=True,timeout=1)
                    state={'unix':time.time(),'owned_directory':str(data),'recordings':db.execute('select count(*) from recordings').fetchone()[0],'chunks':db.execute('select count(*) from chunks').fetchone()[0],'frames':db.execute('select coalesce(sum(frames),0) from chunks').fetchone()[0],'upload_grants':db.execute('select count(*) from recording_cloud_authorizations').fetchone()[0]}
                    db.close()
                    with (OUT/'realtime-persistence.jsonl').open('a') as f:f.write(json.dumps(state)+'\n')
                except sqlite3.Error as error:
                    with (OUT/'realtime-persistence.jsonl').open('a') as f:f.write(json.dumps({'unix':time.time(),'read_only_observation_error':str(error)})+'\n')
        try:runner.wait(timeout=45 if pid else 3)
        except subprocess.TimeoutExpired:pass
code=runner.returncode
after=source();changed=[p for p in sorted(set(before['source_sha256'])|set(after)) if before['source_sha256'].get(p)!=after.get(p)]
result={'head_after':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'source_changed':changed,'unix_finished':time.time(),'runner_exit':code,'requested_wallclock_seconds':1800,'source_sha256':after,'probe':probe_identity,'data_directory':str(data),'status':'PASS' if code==0 and not changed else 'FAIL'}
(OUT/'source-after.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k!='source_sha256'},indent=2),flush=True)
raise SystemExit(0 if result['status']=='PASS' else 1)
