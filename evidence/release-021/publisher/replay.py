import gzip, hashlib, json, runpy, subprocess, tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent
cadence = runpy.run_path(str(root/'scripts/mandarin/score-live-cadence.py'))
flips = runpy.run_path(str(root/'scripts/mandarin/score-preview-reversals.py'))['reversals']
refs = {}
for name in ['continuous.json', 'panel-cohort.json']:
    refs.update({r['id']: r for r in json.loads((root/'evidence/mandarin'/name).read_text())['samples']})
files = sorted((root/'evidence/beta-021/final/fixed15').rglob('auto-*.json.gz'))
files += sorted((root/'evidence/beta-021/final/pressure8').rglob('auto-*.json.gz'))
rows, replay = [], {}
with tempfile.TemporaryDirectory(prefix='saytile-closure-replay-') as temp:
    for index, path in enumerate(files):
        data = gzip.decompress(path.read_bytes()); p = Path(temp)/f'{index}.json'; p.write_bytes(data)
        native = json.loads(data)
        events = json.loads(subprocess.check_output(['/private/tmp/saytile-closure-replay', str(p)]))[str(p)]
        replay[str(path.relative_to(root))] = events
        ref = refs[native['id']]
        wav = root/'.build/mandarin/wav'/(native['id']+'.wav')
        assert hashlib.sha256(wav.read_bytes()).hexdigest() == ref['audio_sha256'] == native['audio_sha256']
        onset, end = cadence['score']['acoustic'](wav); end = min(end, native['endOfFile'])
        result = {'receipt': str(path.relative_to(root)), 'input_sha256': hashlib.sha256(data).hexdigest(), 'algorithms': {}}
        for name, e in events.items():
            fresh = cadence['layer_events'](e, cadence['bigrams'](ref['reference']), onset, end, False)[1]
            metric = cadence['describe'](fresh, onset, end, cadence['active_blocks'](wav), native['rawWorkerEvents'], e)
            result['algorithms'][name] = {'cadence': metric, 'reversals': flips(e, native['endOfFile']),
                                          'final': [x['text'] for x in e if x['kind']=='final']}
        assert result['algorithms']['baseline']['final'] == result['algorithms']['local']['final'] == result['algorithms']['protected']['final']
        rows.append(result)
(out/'replay.json.gz').write_bytes(gzip.compress(json.dumps(replay, ensure_ascii=False, sort_keys=True).encode(),mtime=0))
(out/'results.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2)+'\n')
for r in rows:
    if 'pressure8' in r['receipt']:
        print(r['receipt'], {n:(v['cadence']['longest_s'],len(v['reversals'])) for n,v in r['algorithms'].items()})
print('total reversals', {n:sum(len(r['algorithms'][n]['reversals']) for r in rows) for n in ['baseline','local','protected']})
