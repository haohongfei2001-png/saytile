"""Reproduce and audit the five public FLEURS empty finals through a signed native panel.

The previous build is measured with --baseline. The candidate must keep one worker
per clip, retain the empty recording and copy the transcribed paragraph. A private
pasteboard is required on the candidate. No microphone or production archive is used.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[2]
CASES = ROOT / 'evidence/mandarin-cadence-20261114/candidate/incomplete-segments.json'


def pcm(path):
    with wave.open(str(path)) as source:
        assert (source.getsampwidth(), source.getframerate(), source.getnchannels()) == (2, 16_000, 1)
        return source.readframes(source.getnframes())


def audit(case, folder, expected_sha, baseline):
    fixture = folder / 'fixture.wav'
    assert hashlib.sha256(fixture.read_bytes()).hexdigest() == case['wav_sha256']
    original = pcm(fixture)
    receipt = json.loads((folder / 'visible.json').read_text())
    assert receipt['sha'] == expected_sha and receipt['automatic'] and receipt['providers'] == ['qwen-small']
    assert list(reversed(receipt['recordStates'])) == case['states']
    events = receipt['rawWorkerEvents']
    final = [event for event in events if event['kind'] == 'final']
    assert len(final) == 2 and not final[case['failed_ordinal'] - 1]['text']
    transcript = next(event['text'] for event in final if event['text'])
    assert receipt['frames'][-1]['text'] == ''.join(reversed(receipt['archive'])) == transcript
    if not baseline:
        assert receipt['copiedArchiveParagraphs'] == [transcript]
    ready = sum(event['kind'] == 'ready' for event in events)
    assert ready == (2 if baseline and case['failed_ordinal'] == 1 else 1)
    journal = []
    cursor = 0
    with sqlite3.connect((folder / 'Saytile.sqlite').as_uri() + '?mode=ro', uri=True) as database:
        assert database.execute('pragma integrity_check').fetchone() == ('ok',)
        assert not database.execute('pragma foreign_key_check').fetchall()
        assert database.execute('select count(*) from dispatches').fetchone() == (0,)
        chunks = database.execute('''select c.path, c.frames, t.position, r.recognition_state, r.audio_state
            from transcript_timeline t join recordings r on r.id=t.recording_id
            join chunks c on c.recording_id=r.id order by t.position,c.ordinal''')
        for name, frames, position, state, audio_state in chunks:
            path = folder / 'Audio' / name
            assert not path.is_symlink() and (folder / 'Audio').resolve() in path.resolve().parents
            data = pcm(path)
            assert audio_state == 'available' and len(data) == 2 * frames and frames > 0
            start = original.find(data, cursor)
            assert start >= 0 and start % 2 == 0
            cursor = start + len(data)
            journal.append(dict(position=position, state=state, frames=frames, source_frame=start // 2,
                                pcm_sha256=hashlib.sha256(data).hexdigest()))
    states = dict((chunk['position'], chunk['state']) for chunk in journal)
    assert list(states.values()) == case['states']
    return dict(id=case['id'], wav_sha256=case['wav_sha256'], ready_count=ready,
                first_visible_from_wav_s=receipt['frames'][0]['t'], journal=journal,
                raw_finals=final, archived=transcript, private_copy=receipt.get('copiedArchiveParagraphs'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ('app', 'weights', 'audio', 'out'):
        parser.add_argument('--' + flag, required=True, type=Path)
    parser.add_argument('--existing', type=Path, help='Inspect prior isolated native data directories without launching the app')
    parser.add_argument('--baseline', action='store_true')
    args = parser.parse_args()
    app = args.app.resolve()
    subprocess.run(['codesign', '--verify', '--deep', '--strict', app], check=True)
    sha = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['SaytileSourceRevision']
    rows = []
    for case in json.loads(CASES.read_text())['cases']:
        with tempfile.TemporaryDirectory(prefix='saytile-empty-eos-') as scratch:
            folder = args.existing / case['id'] if args.existing else Path(scratch)
            if not args.existing:
                source = args.audio / (case['id'] + '.wav')
                assert hashlib.sha256(source.read_bytes()).hexdigest() == case['wav_sha256']
                shutil.copyfile(source, folder / 'fixture.wav')
                models = folder / 'LocalModels'
                models.mkdir()
                subprocess.run(['cp', '-cR', args.weights / 'qwen-small', str(models) + '/'], check=True)
                subprocess.run([app / 'Contents/MacOS/Saytile', '--data-directory', folder,
                                '--local-stream-probe', 'auto', '--verify-archive-copy'], check=True, timeout=140)
            rows.append(audit(case, folder, sha, args.baseline))
    args.out.write_text(json.dumps(dict(source=sha, cases=rows), ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
