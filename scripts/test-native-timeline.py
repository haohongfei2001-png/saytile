#!/usr/bin/env python3
"""Seed disposable data and exercise the shipping TextKit view without activating a window."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import sqlite3
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument('--app', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--controls', action='store_true')
p.add_argument('--record', action='store_true', help='Record only the isolated native window across the idle boundary')
args = p.parse_args()
app, out = args.app.resolve(), args.output.resolve()
exe = app / 'Contents/MacOS/Saytile'
out.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='saytile-timeline-review-') as raw:
    tmp = Path(raw)
    data = tmp / 'fixture'
    command = [str(exe), '--data-directory', str(data)]
    subprocess.run(command + ['--smoke-test'], check=True, timeout=30, capture_output=True)
    with sqlite3.connect(data / 'Saytile.sqlite') as db:
        midnight = int(datetime.datetime(2025,1,2).timestamp())
        # Keep midnight inside a four-utterance paragraph. Its first member has
        # an extra 200-second group gap, which must not become the midnight pause.
        boundary = 11946
        for n in range(1, 12001):
            rid = f'00000000-0000-4000-8000-{n:012d}'
            vid = f'00000000-0001-4000-8000-{n:012d}'
            time = midnight + (n - boundary) * 24 + ((n-1)//4 - (boundary-1)//4) * 200
            db.execute('INSERT INTO recordings(id,created_at,sample_rate,preferred_revision,is_recording,recognition_state) VALUES (?,?,16000,?,0,?)', (rid, time, vid, 'completed'))
            texts = ['先把今天想说的记下来。', '嗯，这一句还想再琢磨一下。', '有空的时候，再接着往下说。']
            db.execute('INSERT INTO revisions(id,recording_id,text,origin,created_at) VALUES (?,?,?,?,?)', (vid, rid, texts[n % 3], 'userEdit', time))
        # Check the policy installed by the shipping app at insertion time, before
        # any restart could backfill historical rows using compatibility rules.
        midnight_rows = db.execute('''
            SELECT t.position,t.started,COALESCE(t.ended,t.started+r.total_frames/r.sample_rate),
                   t.day,p.paragraph_start
            FROM transcript_timeline t JOIN recordings r ON r.id=t.recording_id
            LEFT JOIN timeline_paragraphs p ON p.position=t.position
            WHERE t.position IN (?,?) ORDER BY t.position
        ''', (boundary-1, boundary)).fetchall()
        if len(midnight_rows) != 2:
            raise RuntimeError(f'midnight seed owners missing: {midnight_rows!r}')
        before, after = midnight_rows
        if (after[1]-before[2] != 24 or before[3] == after[3]
                or before[4] is None or before[4] != after[4]):
            raise RuntimeError(f'midnight seed must cross days with a 24-second pause in one paragraph: {midnight_rows!r}')
        print(f'TIMELINE_SEED_MIDNIGHT pause=24 positions={before[0]},{after[0]} paragraph={before[4]} metadata=at_capture', flush=True)
    env = dict(os.environ, SAYTILE_TIMELINE_REVIEW='1')
    if args.record:
        env["SAYTILE_RECORD_TIMELINE"] = "1"
    if args.controls:
        probe = tmp / 'ui-control-probe'
        src = Path(__file__).resolve().parents[1] / 'tests/fixtures/NativeUIControlProbe.swift'
        subprocess.run(['swiftc','-swift-version','6','-parse-as-library',str(src),'-o',str(probe)], check=True)
        env['SAYTILE_UI_CONTROL_PROBE'] = str(probe)
    run = subprocess.run(command + ['--ui-review', str(out)], env=env, timeout=150, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / 'run.log').write_text(run.stdout)
    print(run.stdout, end='')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    names = ['timeline-live','timeline-idle','timeline-history','timeline-midnight','timeline-reopened']
    passed = run.returncode == 0 and 'TIMELINE_NATIVE_PASS' in run.stdout and 'TIMELINE_IDLE_STATIONARY' in run.stdout and all((out / (name+'.png')).exists() for name in names)
    receipt = dict(status='PASS' if passed else 'FAIL', source=info['SaytileSourceRevision'], dirty=info['SaytileSourceDirty'], binary_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(), seed_rows=12000, native_ax_copy=args.controls, provider_requests=0, images={n:hashlib.sha256((out / (n+'.png')).read_bytes()).hexdigest() for n in names if (out / (n+'.png')).exists()})
    if args.record and passed:
        encoder = Path(__file__).with_name('encode-timeline-recording.swift')
        movie = out / 'idle-transition.mov'
        subprocess.run(['swift', str(encoder), str(out / 'motion-frames'), str(movie)], check=True)
        receipt['native_window_recording_sha256'] = hashlib.sha256(movie.read_bytes()).hexdigest()
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    raise SystemExit(0 if passed else 1)
