"""Inspect signal and nearby archived words in an explicitly preserved public soak failure."""
import argparse
from array import array
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import runpy
import sqlite3
import wave

parser = argparse.ArgumentParser(description=__doc__)
for key in ('archive', 'receipt', 'manifest', 'wav', 'out'):
    parser.add_argument('--' + key, type=Path, required=True)
a = parser.parse_args()
receipt = json.loads(a.receipt.read_text())
assert a.archive.name.endswith('.failed-archive') and not receipt['passed']
fixture = a.archive / 'fixture.wav'
assert hashlib.sha256(fixture.read_bytes()).hexdigest() == receipt['fixture_sha256']
with wave.open(str(fixture)) as source:
    original = source.readframes(source.getnframes())
score = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'score-local-asr.py'))
rows = {r['id']: r for r in json.loads(a.manifest.read_text())['samples']}
clips = []
position = 0
idle_start, idle_end = [round(t * 16000) for t in receipt['idle']['input_range_seconds']]
for ident in receipt['input_clips']:
    row = rows[ident]
    wav = a.wav / (ident + '.wav')
    assert hashlib.sha256(wav.read_bytes()).hexdigest() == row['audio_sha256']
    with wave.open(str(wav)) as source:
        length = source.getnframes()
    start, end = score['acoustic'](wav)
    clips.append({'id': ident, 'start': position + round(start * 16000), 'end': position + round(end * 16000), 'reference': row['reference']})
    position += length + 16000
    if position == idle_start:
        position += idle_end - idle_start
assert position * 2 == len(original)
with sqlite3.connect((a.archive / 'Saytile.sqlite').resolve().as_uri() + '?mode=ro', uri=True) as db:
    parts = db.execute('''select t.position,c.path,c.frames,r.recognition_state,v.text,r.last_error
        from chunks c join transcript_timeline t on t.recording_id=c.recording_id
        join recordings r on r.id=c.recording_id left join revisions v on v.id=r.preferred_revision
        order by t.position,c.ordinal''').fetchall()
cursor = 0
heads = {}
failed = defaultdict(list)
archived = []
for index, name, frames, state, text, err in parts:
    heads[index] = text or ''
    chunk = a.archive / 'Audio' / name
    assert (a.archive / 'Audio').resolve() in chunk.resolve().parents and not chunk.is_symlink()
    with wave.open(str(chunk)) as w:
        pcm = w.readframes(frames)
    if not pcm:
        continue
    start = original.find(pcm, cursor)
    assert start >= 0 and start % 2 == 0
    cursor = start + len(pcm)
    begin, end = start // 2, cursor // 2
    archived.append((begin, end, index, state))
    if state != 'completed':
        v = array('h', pcm)
        blocks = [v[i:i + 320] for i in range(0, len(v), 320)]
        peak_rms = max(sum(x * x for x in block) / len(block) for block in blocks)
        failed[index].append(dict(start_s=begin / 16000, end_s=end / 16000,
            peak_pcm16=max(abs(x) for x in v), strongest_20ms_rms_dbfs=round(10 * math.log10(max(1e-12, peak_rms) / (32768 ** 2)), 3),
            overlapping_reference_clips=[j for j,c in enumerate(clips) if c['start'] < end and c['end'] > begin],
            state=state, diagnostic=err, retained_head=text))
per_clip = []
for row in clips:
    positions = sorted({idx for lo, hi, idx, state in archived if state == 'completed' and lo < row['end'] and hi > row['start']})
    def pairs(text):
        normalized = score['norm'](text)
        return set(zip(normalized, normalized[1:]))
    matched = pairs(row['reference']) & pairs(''.join(heads[pos] for pos in positions))
    per_clip.append(dict(id=row['id'], signal_s=[round(row['start'] / 16000, 3), round(row['end'] / 16000, 3)],
                         matching_reference_bigrams=len(matched), overlapping_completed_positions=positions))
reference = ''.join(c['reference'] for c in clips)
hypothesis = ''.join(heads[pos] for pos in sorted(heads))
report = dict(source=receipt['source'], model=receipt['model'], fixture_sha256=receipt['fixture_sha256'],
    strict_soak_passed=receipt['passed'], notes='Public PCM only; active spans use the existing sustained -55 dBFS proxy. A matching reference bigram shows associated words only; the archive-wide edit distance includes all missing text. Indices in overlapping_reference_clips are zero based.',
    input_count=len(clips), clips_with_corresponding_text=sum(bool(c['matching_reference_bigrams']) for c in per_clip),
    failed_archive_positions=failed, concatenated_CER=score['rating'](reference, hypothesis), clips=per_clip,
    archive_heads=[dict(position=pos, text=heads[pos]) for pos in sorted(heads)])
a.out.write_text(json.dumps(report, ensure_ascii=False, indent=1) + '\n')
