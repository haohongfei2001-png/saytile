"""Recompute the 0.23 comparison from unchanged scoring functions and raw receipts."""
import collections
import gzip
import hashlib
import json
from pathlib import Path
import runpy
import tempfile
import shutil

ROOT = Path(__file__).resolve().parents[2]
E = ROOT / 'evidence/experience-023'
base = runpy.run_path(str(ROOT / 'scripts/score-local-asr.py'))
cadence = runpy.run_path(str(ROOT / 'scripts/mandarin/score-live-cadence.py'))
reverse = runpy.run_path(str(ROOT / 'scripts/mandarin/score-preview-reversals.py'))
rate, quant = base['rating'], base['quant']
manifest = E / 'setup/panel16.json'
refs = json.loads(manifest.read_text())['samples']
audio = Path('/private/tmp/saytile-release-021/.build/mandarin/wav')
report = dict(scope='Public PCM, native AppKit, M5; no live microphone. Reference/normalization unchanged.', routes={})
for label, model in [('qwen-022', 'qwen-small'), ('qwen-preview', 'qwen-small'), ('nemotron', 'nemotron-metal')]:
    with tempfile.TemporaryDirectory(prefix='saytile-report-') as tmp:
        flat = Path(tmp)
        corpus, resources, provenance = [], [], []
        for ref in refs:
            if label == 'qwen-022':
                root = E / 'native/repeated4' if (E / 'native/repeated4' / label / ref['id']).exists() else E / 'native/paired16'
            else:
                root = E / 'final/paired16'
            folder = root / label / ref['id']
            source = folder / f'{model}-{ref["id"]}.json'
            value = json.loads(source.read_text())
            assert value['exit_code'] == 0 and value['providers'] == [model]
            assert value['audio_sha256'] == ref['audio_sha256']
            shutil.copyfile(source, flat / source.name)
            corpus.append(value)
            resources.append(json.loads((folder / 'process.json').read_text()))
            provenance.append(dict(receipt=str(source.relative_to(ROOT)), sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
        sha = corpus[0]['sha']
        assert all(v['sha'] == sha for v in corpus)
        score = cadence['measure'](manifest, audio, flat, sha, model=model, automatic=False)
        counts = collections.Counter()
        for ref, r in zip(refs[:15], corpus[:15]):
            counts.update(rate(ref['reference'], ''.join(reversed(r['archive']))))
        partials = [r['publications'] for r in corpus]
        score['normal15'] = dict(**base['pooled'](counts),
            first_display_s=quant([r['display']['first_s'] for r in score['rows'][:15] if r['display']['first_s'] is not None]),
            eos_after_file_s=quant([r['after_file_s'] for r in score['rows'][:15]]),
            preview_reversals=sum(len(reverse['reversals'](r['publications'], r['endOfFile'])) for r in corpus[:15]),
            revisions=[base['changes']([e['text'] for e in r['publications'] if e['t'] < r['endOfFile']]) for r in corpus[:15]],
            combined_cpu_s=round(sum(r['combined_cpu_s'] for r in resources[:15]), 3),
            peak_simultaneous_footprint_MiB=max(r['peak_simultaneous_footprint_MiB'] for r in resources[:15]))
        score['long_clip'] = dict(metrics=score['rows'][-1], resource=resources[-1],
            reversals=reverse['reversals'](corpus[-1]['publications'], corpus[-1]['endOfFile']))
        score['provenance'] = provenance
        report['routes'][label] = score
(E / 'final/native-comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')

manifest440 = json.loads(gzip.decompress((ROOT / 'evidence/release-021/quality/input440.json.gz').read_bytes()))
old = [json.loads(l) for l in gzip.decompress((ROOT / 'evidence/performance-022/final/quality/product440.jsonl.gz').read_bytes()).splitlines()]
quality = {}
for model in ['qwen-small', 'nemotron-metal']:
    path = E / 'final' / f'product440-{model}.jsonl'
    if not path.exists(): continue
    rows = [json.loads(l) for l in path.read_text().splitlines()]
    if len(rows) != len(manifest440): continue
    groups = collections.defaultdict(collections.Counter)
    cases = []
    for ref, row in zip(manifest440, rows):
        assert ref['id'] == row['id'] and row['providers'] == [model]
        counts = rate(ref['reference'], row['text'])
        group = 'derived20' if ref['source'] in ('quiet', 'noise15db') else 'original420'
        for key in [ref['source'], group]:
            groups[key].update(counts); groups[key]['rows'] += 1
        cases.append(dict(id=ref['id'],source=ref['source'],reference=ref['reference'],text=row['text'],states=row['states'],**counts))
    quality[model] = dict(rows=len(rows), groups={k:dict(rows=c['rows'],**base['pooled'](c)) for k,c in groups.items()},
        failed_rows=[r for r in rows if 'failed' in r['states']],
        baseline_final_state_identical=sum(r['text']==b['text'] and r['states']==b['states'] for r,b in zip(rows,old)),
        largest_errors=sorted(cases,key=lambda r:r['errors'],reverse=True)[:12],
        all_cases=cases)
(E / 'final/quality-comparison.json').write_text(json.dumps(quality,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:r['normal15'] for k,r in report['routes'].items()},ensure_ascii=False,indent=2))
print(json.dumps({k:r['groups']['original420'] for k,r in quality.items()},ensure_ascii=False))

# The bounded follow-up is reported separately, including the failed arm. It
# must never replace the original fifteen-clip first-output distribution.
variance = E / 'final/variance'
if (variance / 'complete.json').exists():
    followup = dict(scope='Three serial AB/BA/AB pairs; two first-output outliers and 1.33-core ordinary contention',
                    completion=json.loads((variance / 'complete.json').read_text()), samples={})
    for sample in sorted(p for p in variance.iterdir() if p.is_dir()):
        pairs = []
        for pair in sorted(p for p in sample.iterdir() if p.is_dir()):
            arms, finals = {}, {}
            for arm in sorted(p for p in pair.iterdir() if p.is_dir()):
                path = arm / 'cadence.json'
                if not path.exists():
                    arms[arm.name] = dict(status='FAIL', evidence=str(arm.relative_to(ROOT)))
                    continue
                result = json.loads(path.read_text())['rows'][0]
                process = json.loads((arm / 'native/process.json').read_text())
                raw = json.loads((arm / 'native' / f'qwen-small-{sample.name}.json').read_text())
                finals[arm.name] = raw['archive']
                arms[arm.name] = dict(status='PASS', source=raw['sha'],
                    first_s=result['display']['first_s'], worker_first_s=result['worker']['first_s'],
                    display_max_gap_s=result['display']['longest_s'],
                    display_gap_p95_s=result['display']['gap_s']['p95'], eos_s=result['after_file_s'],
                    cpu_s=process['combined_cpu_s'], footprint_MiB=process['peak_simultaneous_footprint_MiB'],
                    preview_reversals=len(reverse['reversals'](raw['publications'],raw['endOfFile'])),
                    evidence=str(arm.relative_to(ROOT)))
                if (arm / 'load.json').exists():
                    load = json.loads((arm / 'load.json').read_text())
                    arms[arm.name].update(load_cores=load['observed_cores'], load_target_met=load['target_met'])
            pairs.append(dict(pair=int(pair.name), arms=arms,
                              final_identical=finals['qwen-022']==finals['qwen-preview'] if len(finals)==2 else None))
        followup['samples'][sample.name] = pairs
    (E / 'final/variance-summary.json').write_text(json.dumps(followup,ensure_ascii=False,indent=2)+'\n')
