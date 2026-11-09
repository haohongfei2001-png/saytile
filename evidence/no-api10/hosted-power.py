"""Test a paused controller through kernel sleep only on a disposable hosted macOS runner."""
import datetime
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import time

if not (os.getenv('GITHUB_ACTIONS') == 'true' and os.getenv('SAYTILE_HOST_TYPE') == 'github-hosted' and os.getenv('RUNNER_OS') == 'macOS'):
    raise SystemExit('Dedicated GitHub macOS runner required')
root = Path(os.environ['RUNNER_TEMP'])/'power-receipt'
root.mkdir(exist_ok=True)
def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=15)
def events():
    log = root/'power-events.jsonl'
    return [json.loads(s) for s in log.read_text().splitlines()] if log.exists() else []
def save(data):
    (root/'power.json').write_text(json.dumps(data, indent=2)+'\n')
provenance = dict(source=run('git','rev-parse','HEAD').stdout.strip(), host_model=run('sysctl','-n','hw.model').stdout.strip(),
                  capabilities=run('pmset','-g','cap').stdout.splitlines(), private_audio_opened=False)
with tempfile.TemporaryDirectory() as td:
    exe = Path(td)/'paused'
    flags = runpy.run_path('scripts/test-input-native.py')['production_flags']()
    subprocess.run(['swiftc','-swift-version','6','-parse-as-library','-I','Sources/CSQLite',*flags,
                    'evidence/no-api10/HostedPaused.swift','-o',exe],check=True)
    process = subprocess.Popen([exe,root])
    try:
        for _ in range(40):
            if events() or process.poll() is not None: break
            time.sleep(.25)
        assert events() and events()[0]['paused'] and not events()[0]['running'], 'paused observer not armed'
        result = dict(**provenance, status='BLOCKED', reason='runner lacks scheduled hardware wake or system sleep support')
        save(result)
        if 'sleep' in {row.strip() for row in provenance['capabilities']}:
            wake = (datetime.datetime.now()+datetime.timedelta(seconds=40)).strftime('%m/%d/%y %H:%M:%S')
            owner = 'app.saytile.hosted.'+os.environ['GITHUB_RUN_ID']
            schedule = ['sudo','-n','/usr/bin/pmset','schedule']
            scheduled = run(*schedule,'wake',wake,owner)
            try:
                result['schedule_exit']=scheduled.returncode
                if scheduled.returncode == 0 and owner in run('pmset','-g','sched').stdout:
                    sleep = run('sudo','-n','/usr/bin/pmset','sleepnow')
                    result['sleep_request_exit'] = sleep.returncode
                    if sleep.returncode == 0:
                        deadline=time.time()+65
                        while time.time()<deadline:
                            seq=events()
                            if any(x['event']=='didWakeSettled' for x in seq): break
                            time.sleep(.5)
                        seq=events()
                        pair=next((x for x in seq if x['event']=='didWakeSettled' and x['kernelWake']>x['kernelSleep']>=seq[0]['unix']
                                   and any(y['event']=='willSleep' and y['unix']<=x['unix'] for y in seq)),None)
                        if pair:
                            result.update(status='PASS' if pair['paused'] and not pair['running'] else 'FAIL',reason='paired OS notifications and kernel timestamps observed')
                        else:result['reason']='runner did not report a new matching kernel sleep and wake'
            finally:
                if scheduled.returncode==0:run(*schedule,'cancel','wake',wake,owner)
        save(result)
    finally:
        (root/'done').touch()
        process.wait(timeout=12)
print(json.dumps(result))
if result['status']=='FAIL':raise SystemExit(1)
