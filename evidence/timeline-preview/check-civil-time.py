"""Exercise SQLite grouping triggers from the shipped app across two timezone transitions."""
import datetime as dt
import json
import os
from pathlib import Path
import plistlib
import sqlite3
import subprocess
import sys
import tempfile

app, out = map(Path, sys.argv[1:])
zone = 'America/Los_Angeles'
times = ['2025-03-09T09:59:59+00:00', '2025-03-09T10:00:00+00:00',
         '2025-11-02T08:59:59+00:00','2025-11-02T09:00:00+00:00','2025-11-02T09:03:00+00:00']
with tempfile.TemporaryDirectory(prefix='saytile-timeline-calendar-') as tmp:
    def start(tz):
        log = subprocess.run([app/'Contents/MacOS/Saytile','--data-directory',tmp,'--smoke-test'],
            capture_output=True, text=True, timeout=30, check=True, env=dict(os.environ,TZ=tz))
        assert 'SAYTILE_SMOKE_OK' in log.stdout
    start(zone)
    # SQLite's date('localtime') consults process localtime. Insert through the
    # exact schema and capture triggers the packaged executable installed.
    seed = """
import datetime, json, os, sqlite3, sys, time, uuid
time.tzset()
with sqlite3.connect(sys.argv[1]) as db:
    for stamp in json.loads(sys.argv[2]):
        epoch = datetime.datetime.fromisoformat(stamp).timestamp()
        db.execute("INSERT INTO recordings(id,created_at,sample_rate,is_recording,recognition_state) VALUES (?,?,16000,0,'completed')",(str(uuid.uuid4()).upper(),epoch))
"""
    dbpath = Path(tmp)/'Saytile.sqlite'
    subprocess.run([sys.executable,'-c',seed,dbpath,json.dumps(times)],check=True,env=dict(os.environ,TZ=zone))
    def rows():
        with sqlite3.connect(dbpath) as db:
            return db.execute('select group_start,day,utc_offset from transcript_timeline order by position').fetchall()
    initial = rows()
    assert [r[0] for r in initial] == [1,1,3,3,5]
    assert [r[2] for r in initial] == [-28800,-25200,-25200,-28800,-28800]
    start('Asia/Shanghai')
    assert rows()==initial
    source = plistlib.loads((app/'Contents/Info.plist').read_bytes())['SaytileSourceRevision']
    out.write_text(json.dumps(dict(status='PASS',source=source,utc=times,group_day_offset=initial,
        seed_timezone=zone,reopen_timezone='Asia/Shanghai',same_calendar_labels_after_reopen=True),indent=2)+'\n')
