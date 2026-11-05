#!/usr/bin/env python3
"""Small Linux fault-injection experiment for the design, not macOS validation.

Generates synthetic PCM; never records a microphone. Tests crash-recoverable
file layout and state invariants. Does not simulate power failure or validate
APFS, Core Audio, SpeechAnalyzer, energy usage, or actual text insertion.
"""
from pathlib import Path
import hashlib
import json
import os
import sqlite3
import struct
import subprocess
import sys
import tempfile

def pcm(seconds=3):
    return b''.join(struct.pack('<h', (i * 37) % 30000 - 15000)
                    for i in range(16000 * seconds))

def crash_writer(directory, mode):
    root = Path(directory)
    meta = dict(id='chunk-1', session='session-1', first_sample=0,
                sample_rate=16000, channels=1, bytes_per_sample=2)
    m = root / 'chunk-1.json'
    with m.open('w') as f:
        json.dump(meta, f); f.flush(); os.fsync(f.fileno())
    fd = os.open(root / 'chunk-1.pcm.part', os.O_WRONLY | os.O_CREAT, 0o600)
    data = pcm()
    pos = 0
    while pos < len(data):
        pos += os.write(fd, data[pos:])
    os.fsync(fd)
    if mode == 'torn_tail':
        os.write(fd, b'\x12')
    # Process ends before registering the audio in SQLite / sealing the file.
    os._exit(47)

def recover(root):
    recovered = []
    for sidecar in root.glob('*.json'):
        meta = json.loads(sidecar.read_text())
        f = root / (meta['id'] + '.pcm.part')
        if not f.exists():
            continue
        stride = meta['channels'] * meta['bytes_per_sample']
        whole = (f.stat().st_size // stride) * stride
        with f.open('r+b') as stream:
            stream.truncate(whole)
        recovered.append((meta, f.read_bytes()))
    return recovered

def run():
    results = []
    def check(name, condition, detail):
        assert condition, name
        results.append(dict(name=name, result='PASS', detail=detail))

    with tempfile.TemporaryDirectory(prefix='voice-design-lab-') as directory:
        root = Path(directory)
        for mode in ('orphan', 'torn_tail'):
            p = root / mode; p.mkdir()
            child = subprocess.run([sys.executable, __file__, '--crash-writer', str(p), mode])
            entries = recover(p)
            check('crash_recovery_' + mode,
                  child.returncode == 47 and len(entries) == 1 and entries[0][1] == pcm(),
                  'Recovered 48,000 generated PCM frames; odd trailing byte removed when present.')

        schema = Path(__file__).with_name('schema.sql').read_text()
        db = sqlite3.connect(root / 'state.sqlite')
        db.executescript(schema)
        check('schema_executes', db.execute('PRAGMA foreign_key_check').fetchall() == [],
              'Proposed SQL schema executes with foreign keys enabled.')
        db.execute("INSERT INTO capture_sessions(id,started_at,device_uid,sample_rate,content_generation) VALUES ('s','demo','synthetic',16000,1)")
        for u, start in [('u1',0),('u2',48000)]:
            db.execute('INSERT INTO utterances(id,session_id,group_id,core_start_sample,context_start_sample,content_generation) VALUES (?,?,?,?,?,?)',
                       (u,'s','g',start,start,1))
        job = ('j1','u1','demo','model-v1',1,1,'queued')
        db.execute('INSERT INTO recognition_jobs(id,utterance_id,engine,model_revision,source_generation,request_revision,state) VALUES (?,?,?,?,?,?,?)',job)
        db.execute('INSERT OR IGNORE INTO recognition_jobs(id,utterance_id,engine,model_revision,source_generation,request_revision,state) VALUES (?,?,?,?,?,?,?)',
                   ('duplicate',)+job[1:])
        check('job_idempotency', db.execute('SELECT count(*) FROM recognition_jobs').fetchone()[0] == 1,
              'Re-enqueueing one source/model revision produces one job.')

        for rid,u,kind,text in [('r1','u1','asr_final','先保存，再识别。'),('r2','u2','asr_final','先保存，再识别。'),
                                ('edit','u1','user_edit','先保存原音，再识别。')]:
            db.execute('INSERT INTO transcript_revisions(id,utterance_id,revision_no,origin,text,created_at) VALUES (?,?,?,?,?,?)',
                       (rid,u,1,kind,text,'demo'))
        db.execute("UPDATE utterances SET preferred_revision_id='edit' WHERE id='u1'")
        check('repeated_speech_is_not_deduplicated',
              db.execute("SELECT count(*) FROM transcript_revisions WHERE origin='asr_final' AND text=?",('先保存，再识别。',)).fetchone()[0] == 2,
              'Equal words in two utterances remain two separate audio records.')

        # A late ASR result is a version, not an overwrite of the chosen edit.
        db.execute("INSERT INTO transcript_revisions(id,utterance_id,revision_no,origin,text,created_at) VALUES ('late','u1',2,'asr_final','先保存在识别','demo')")
        check('user_edit_survives_late_asr',
              db.execute("SELECT preferred_revision_id FROM utterances WHERE id='u1'").fetchone()[0] == 'edit',
              'Later recognition version does not replace the user-selected edit.')

        db.execute("UPDATE recognition_jobs SET active_attempt='attempt-new',state='running' WHERE id='j1'")
        def accept_completion(attempt, generation):
            current = int(db.execute("SELECT value FROM store_meta WHERE key='content_generation'").fetchone()[0])
            active = db.execute("SELECT active_attempt FROM recognition_jobs WHERE id='j1'").fetchone()[0]
            return attempt == active and generation == current
        check('stale_attempt_ignored', not accept_completion('attempt-old',1),
              'A cancelled/replaced worker cannot commit its delayed completion.')
        db.execute("UPDATE store_meta SET value='2' WHERE key='content_generation'")
        check('delete_generation_blocks_resurrection', not accept_completion('attempt-new',1),
              'A completion from a prior content generation cannot recreate erased history.')

        for oid,state in [('op-old','dispatching'),('op-next','prepared')]:
            db.execute('INSERT INTO insertion_operations(id,utterance_id,revision_id,text_start,text_end,state,created_at) VALUES (?,?,?,?,?,?,?)',
                       (oid,'u1','edit',0,10,state,'demo'))
        db.execute("UPDATE insertion_operations SET state='unverified' WHERE state='dispatching'")
        check('uncertain_insert_does_not_replay_or_block_next',
              db.execute("SELECT id,state FROM insertion_operations ORDER BY id").fetchall() == [('op-next','prepared'),('op-old','unverified')],
              'After restart, uncertain paste is not replayed; another insertion stays independently eligible.')

        db.execute('CREATE VIRTUAL TABLE search_test USING fts5(text, tokenize="trigram")')
        db.execute('INSERT INTO search_test VALUES (?)',('先保存原音，再识别。',))
        three = db.execute('SELECT count(*) FROM search_test WHERE text MATCH ?',('保存原',)).fetchone()[0]
        two = db.execute('SELECT count(*) FROM search_test WHERE text LIKE ?',('%原音%',)).fetchone()[0]
        check('chinese_short_query_fallback',three == 1 and two == 1,
              'Three-character trigram query and two-character LIKE fallback both return the record.')
        db.commit()

    report = dict(scope='Design experiment: Linux synthetic PCM and SQLite only',
                  native_audio_asr_input_energy_measured=False,
                  sample_rate=16000, recovered_frames_per_crash=48000,
                  fixture_sha256=hashlib.sha256(pcm()).hexdigest(),
                  passed=len(results), total=len(results), checks=results)
    print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--crash-writer':
        crash_writer(sys.argv[2],sys.argv[3])
    else:
        run()
