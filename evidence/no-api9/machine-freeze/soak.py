"""Measure 72 hours of the extracted application at idle using a new private test store."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time

out = Path(sys.argv[1])
app = Path(sys.argv[2])
seconds = 72 * 3600
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
binary = app / 'Contents/MacOS/Saytile'
identity = {'source': info['SaytileSourceRevision'], 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
assert identity == {'source':'dc26fe3c59ba55994d29e99ada8d2f0b49ad9886','binary_sha256':'cb3b7a38dae90fccd323b57ee746baedbfcb43b457e0b30dbdcbaedffd35ed00'}
out.mkdir(parents=True, exist_ok=False)
started = time.time()
deadline = started + seconds
def utc(t):
    return datetime.datetime.fromtimestamp(t,datetime.timezone.utc).isoformat()
def save(file, data):
    tmp = out/(file+'.tmp')
    tmp.write_text(json.dumps(data,indent=2)+'\n')
    tmp.replace(out/file)
def rowcount(store):
    with sqlite3.connect((store/'Saytile.sqlite').resolve().as_uri()+'?mode=ro',uri=True) as db:
        return db.execute('select count(*) from recordings').fetchone()[0]
with tempfile.TemporaryDirectory(prefix='saytile-machine-idle-') as td:
    store = Path(td)/'data'
    with (out/'launch.log').open('x') as log:
        proc = subprocess.Popen([str(binary),'--data-directory',str(store)],stdout=log,stderr=subprocess.STDOUT)
    try:
        save('interval.json', {**identity,'start_utc':utc(started),'due_utc':utc(deadline),'pid':proc.pid,'scope':'Actual paused App. Wall time includes system sleep. Per-process resource use, not whole-device energy.'})
        for i in range(120):
            if 'SAYTILE_ISOLATED_LAUNCH cloud_enabled=false automatic_recovery=false shortcut=disabled visible_panel=false hotkey_registered=false' in (out/'launch.log').read_text(): break
            if proc.poll() is not None: raise RuntimeError('early exit')
            time.sleep(.25)
        else: raise RuntimeError('isolated launch not confirmed')
        samples = []
        while True:
            now = time.time()
            if proc.poll() is not None: raise RuntimeError('exited during observation')
            rss, cpu = subprocess.check_output(['ps','-p',str(proc.pid),'-o','rss=,time='],text=True).split()
            row={'utc':utc(now),'wall_seconds':round(now-started,2),'rss_kib':int(rss),'process_cpu_time':cpu,'recordings':rowcount(store)}
            if row['recordings'] or list(store.rglob('*.wav')): raise RuntimeError('unexpected recording in paused Store')
            with (out/'samples.jsonl').open('a') as f: print(json.dumps(row),file=f,flush=True)
            samples.append(row)
            if now >= deadline: break
            time.sleep(min(60,deadline-now))
        with sqlite3.connect((store/'Saytile.sqlite').resolve().as_uri()+'?mode=ro',uri=True) as db:
            assert db.execute('pragma integrity_check').fetchone()[0]=='ok'
        save('result.json',{**identity,'status':'PASS','scope':'Same paused process survived the 72-hour wall interval; resource distribution descriptive.', 'start_utc':utc(started),'end_utc':utc(now),'samples':len(samples),'wall_seconds':now-started,'max_rss_kib':max(r['rss_kib'] for r in samples),'last':samples[-1]})
    except BaseException as exc:
        save('result.json',{**identity,'status':'FAIL' if proc.poll() is not None else 'BLOCKED','scope':'72-hour observation incomplete','cause':str(exc),'elapsed_wall_seconds':time.time()-started})
        raise
    finally:
        if proc.poll() is None: proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=15)
