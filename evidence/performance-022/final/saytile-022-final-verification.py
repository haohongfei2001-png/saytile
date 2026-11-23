import collections
import gzip
import hashlib
import json
import os
from pathlib import Path
import plistlib
import runpy
import subprocess
import tempfile
import time
import sys

ROOT = Path('/private/tmp/saytile-performance-022')
APP = Path('/tmp/saytile-022-final/Saytile.app')
OUT = ROOT / 'evidence/performance-022/final'
AUDIO = Path('/private/tmp/saytile-release-021/.build/mandarin/wav')
WEIGHTS = Path('/private/tmp/saytile-release-021/.build/local-asr/weights')
META = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
SHA = META['SaytileSourceRevision']
assert SHA == 'a90601b79e59333c97982e200dfb69e541c2bf95' and not META['SaytileSourceDirty']
RESUME = "--resume" in sys.argv
OUT.mkdir(parents=True, exist_ok=RESUME)
measure = runpy.run_path(str(ROOT / 'scripts/mandarin/measure-preview-cost.py'))['public_run']
score = runpy.run_path(str(ROOT / 'scripts/mandarin/score-live-cadence.py'))['measure']
metrics = runpy.run_path(str(ROOT / 'scripts/score-local-asr.py'))
reverse = runpy.run_path(str(ROOT / 'scripts/mandarin/score-preview-reversals.py'))['reversals']
manifest = ROOT / 'evidence/mandarin/panel-cohort.json'
samples = json.loads(manifest.read_text())['samples']
normal = OUT / 'normal15'
normal.mkdir(exist_ok=RESUME)
failures = []
for sample in samples:
    ident = sample['id']
    try:
        if RESUME and (normal / ident / ('auto-qwen-small-' + ident + '.json')).exists():
            print('reuse saved raw result', ident, flush=True)
        else:
            measure(APP, manifest, ident, WEIGHTS, AUDIO, normal / ident)
    except Exception as error:
        failures.append(dict(id=ident, error=repr(error)))
    print('normal', ident, flush=True)
(OUT / 'normal-failures.json').write_text(json.dumps(failures, indent=2))
if not failures:
    with tempfile.TemporaryDirectory(prefix='saytile-022-score-') as tmp:
        tmp = Path(tmp)
        for p in normal.glob('*/auto-*.json'):
            os.link(p, tmp / p.name)
        cadence = score(manifest, AUDIO, tmp, SHA)
    total = collections.Counter()
    for row in cadence['rows']:
        total.update(row['final_CER'])
    same = []
    reversals = []
    for sample in samples:
        ident = sample['id']
        name = 'auto-qwen-small-' + ident + '.json'
        raw = json.loads((normal / ident / name).read_text())
        old = json.loads(gzip.decompress((ROOT / 'evidence/release-021/cadence/raw/normal15-complete' / ident / (name + '.gz')).read_bytes()))
        same.append(dict(id=ident, same_archive=raw['archive'] == old['archive'], same_states=raw['recordStates'] == old['recordStates']))
        reversals.append(dict(id=ident, events=reverse(raw['publications'], raw['endOfFile'])))
    cadence['pooled_CER'] = dict(total, cer=total['errors']/total['reference_units'])
    cadence['eos_s'] = metrics['quant']([row['after_file_s'] for row in cadence['rows']])
    cadence['baseline_exact_comparison'] = same
    cadence['reversals'] = reversals
    (OUT / 'normal15.json').write_text(json.dumps(cadence, ensure_ascii=False, indent=2))
    print('normal15 scored', cadence['pooled_CER'], cadence['summary']['display'], flush=True)

# Instrumented stage isolation is separate from uninstrumented latency acceptance.
load = runpy.run_path(str(ROOT / 'scripts/mandarin/measure-loaded-preview.py'))['fixed_load']
time.sleep(60)
try:
    with load(Path('/private/tmp/saytile-021-cpu-load'), 8, OUT / 'trace-load.json'):
        measure(APP, ROOT / 'evidence/mandarin/continuous.json', 'continuous-public-5', WEIGHTS, AUDIO, OUT / 'trace', trace=True)
except Exception as error:
    (OUT / 'trace-failure.json').write_text(json.dumps(dict(error=repr(error))))
trace = OUT / 'trace/auto-qwen-small-continuous-public-5.json'
if trace.exists():
    subprocess.run(['python3', str(ROOT / 'scripts/mandarin/summarize-pipeline-trace.py'), str(trace), str(OUT / 'trace')], check=True)

# Exact final library + signed baseline-identical decoder. Accelerated quality only.
quality = OUT / 'quality'
quality.mkdir()
rows = json.loads(gzip.decompress((ROOT / 'evidence/release-021/quality/input440.json.gz').read_bytes()))
manifest440 = quality / 'input440.json'
manifest440.write_text(json.dumps(rows, ensure_ascii=False))
target = quality / 'product440.jsonl'
command = ['/private/tmp/saytile-022-final-cohort', 'qwen-small', 'product', str(manifest440), str(AUDIO), str(WEIGHTS), str(APP / 'Contents/Helpers'), str(target)]
library = Path('/private/tmp/saytile-022-probe-build/out/Products/Debug/libSaytileKit.a')
receipt = dict(source=SHA, source_dirty=False, command=command, cwd=str(APP / 'Contents/Resources'),
    probe_sha256=hashlib.sha256(Path(command[0]).read_bytes()).hexdigest(),
    library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),
    worker_sha256=hashlib.sha256((APP / 'Contents/Helpers/SaytileModelWorker').read_bytes()).hexdigest(),
    input_manifest_sha256=hashlib.sha256(manifest440.read_bytes()).hexdigest(),
    scope='Accelerated quality, not wall-clock latency or a physical microphone test')
(quality / 'invocation.json').write_text(json.dumps(receipt, indent=2))
print('quality440 starting', flush=True)
with (quality / 'product440.log').open('w') as log:
    result = subprocess.run(command, cwd=APP / 'Contents/Resources', stdout=log, stderr=subprocess.STDOUT)
receipt['exit_code'] = result.returncode
(quality / 'invocation.json').write_text(json.dumps(receipt, indent=2))
assert result.returncode == 0, result.returncode
actual = [json.loads(line) for line in target.read_text().splitlines()]
baseline = [json.loads(line) for line in gzip.decompress((ROOT / 'evidence/release-021/quality/product440.jsonl.gz').read_bytes()).decode().splitlines()]
assert [r['id'] for r in actual] == [r['id'] for r in rows] == [r['id'] for r in baseline]
groups = collections.defaultdict(collections.Counter)
differences, failed = [], []
for ref, new, old in zip(rows, actual, baseline):
    value = metrics['rating'](ref['reference'], new['text'])
    for group in [ref['source'], 'derived20' if ref['source'] in ('quiet', 'noise15db') else 'original420']:
        groups[group].update(value)
        groups[group]['rows'] += 1
    if any(new[k] != old[k] for k in ('text', 'states', 'providers')):
        differences.append(dict(id=ref['id'], before=old, after=new))
    if 'failed' in new['states']:
        failed.append(new)
report = dict(product_source=SHA, baseline_source='06997bd613ac4dede54450702385259f3bc02f2c',
    rows=len(actual), identical_final_and_state_rows=len(actual)-len(differences), differences=differences, failed=failed,
    groups={k:dict(v, cer=v['errors']/v['reference_units']) for k,v in groups.items()}, scope=receipt['scope'])
(quality / 'quality440.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print('quality440 complete', report['groups']['original420'], 'differences', len(differences), flush=True)
