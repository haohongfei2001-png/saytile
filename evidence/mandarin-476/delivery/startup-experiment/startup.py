#!/usr/bin/env python3
"""Isolated direct-helper startup only. Run after the GPU coordinator releases it."""
from pathlib import Path
import argparse, ctypes, hashlib, json, os, queue, statistics, struct
import subprocess, threading, time, wave

HERE = Path(__file__).resolve().parent
REPO = Path('/private/tmp/saytile-preview-013')
BASIS = '0fbca1d892bbc8aa550c4439b8cfcb045af825ae'
OLD = Path('/private/tmp/saytile-qwen-load476-control/SaytileModelWorker')
NEW = HERE / 'SaytileModelWorker'
REVISION = json.loads((REPO / 'Sources/SaytileKit/Resources/LocalASR/qwen-small.json').read_text())['revision']
WEIGHTS = Path('/private/tmp/saytile-local-quality-20261114/.build/local-asr/weights/qwen-small') / REVISION
CASES = json.loads((REPO / 'evidence/mandarin-cadence-20261114/worker-cases.json').read_text())['samples']
LIBPROC = ctypes.CDLL('/usr/lib/libproc.dylib')
LIBSYSTEM = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
class Timebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]
TIMEBASE = Timebase()
assert LIBSYSTEM.mach_timebase_info(ctypes.byref(TIMEBASE)) == 0
EXPECTED_LOGS = {
    'Found 1 safetensor files', 'Loading: model.safetensors',
    'Applied weights to audio encoder (18 layers, 301 tensors)',
    'Applied weights to text decoder (28 layers, 704 tensors)'
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def usage(pid):
    info = (ctypes.c_uint64 * 12)()
    if LIBPROC.proc_pid_rusage(pid, 0, ctypes.byref(info)) != 0:
        return None
    return dict(cpu_s=(info[2] + info[3]) * TIMEBASE.numer / TIMEBASE.denom / 1e9,
                cpu_mach_ticks=info[2] + info[3], resident_bytes=info[8],
                physical_bytes=info[9], pageins=info[6])

def run(arm, item, index, output):
    helper = OLD if arm == 'old' else NEW
    wav = Path('/private/tmp/saytile-cadence-measure/worker-wavs') / (item['id'] + '.wav')
    assert sha(wav) == item['audio_sha256']
    with wave.open(str(wav)) as audio:
        assert (audio.getframerate(), audio.getnchannels(), audio.getsampwidth()) == (16000, 1, 2)
        pcm = audio.readframes(12800)
    assert len(pcm) == 25600
    load_average = os.getloadavg()
    start = time.monotonic()
    samples, nonprotocol = [], []
    events = queue.Queue()
    stopped = threading.Event()
    with open(output / f'{index:02d}-{arm}.stderr', 'wb') as stderr:
        proc = subprocess.Popen([str(helper), 'qwen-small', str(WEIGHTS), '8000'],
                                cwd=helper.parent, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=stderr, bufsize=0,
                                env=dict(os.environ, SAYTILE_WORKER_TIMING='1'))
        def read_output():
            for raw in iter(proc.stdout.readline, b''):
                stamp = time.monotonic()
                try:
                    events.put((stamp, json.loads(raw)))
                except json.JSONDecodeError:
                    nonprotocol.append(raw.decode().strip())
            events.put((time.monotonic(), None))
        def sample():
            while not stopped.is_set():
                value = usage(proc.pid)
                if value is not None:
                    samples.append(dict(t=time.monotonic() - start, **value))
                stopped.wait(0.020)
        reader = threading.Thread(target=read_output, daemon=True)
        sampler = threading.Thread(target=sample, daemon=True)
        reader.start(); sampler.start()
        def event(kind):
            stamp, value = events.get(timeout=45)
            assert value is not None and value['kind'] == kind, (kind, value)
            return stamp, value
        try:
            ready_at, ready = event('ready')
            ready_usage = usage(proc.pid)
            sent_at = time.monotonic()
            proc.stdin.write(struct.pack('<I', len(pcm)) + pcm); proc.stdin.flush()
            partial_at, partial = event('partial')
            assert partial['frames'] == 12800 and partial['text']
            partial_usage = usage(proc.pid)
            final_sent = time.monotonic()
            proc.stdin.write(bytes(4)); proc.stdin.flush()
            final_at, final = event('final')
            assert final['frames'] == 12800 and final['text'] == partial['text']
            final_usage = usage(proc.pid)
            proc.stdin.close()
            proc.wait(timeout=10)
            reader.join(timeout=5)
            assert proc.returncode == 0
            assert set(nonprotocol) <= EXPECTED_LOGS, nonprotocol
        finally:
            stopped.set(); sampler.join(timeout=2)
            if proc.poll() is None:
                proc.kill(); proc.wait()
        return dict(arm=arm, input=item['id'], audio_sha256=item['audio_sha256'],
                    initial_system_load_average=load_average,
                    helper_sha256=sha(helper), startup_ready_s=ready_at-start,
                    first_pcm_to_visible_s=partial_at-sent_at,
                    startup_to_visible_s=partial_at-start,
                    same_pcm_eos_s=final_at-final_sent,
                    ready_usage=ready_usage, first_usage=partial_usage, final_usage=final_usage,
                    sampled_peak_resident_bytes=max(s['resident_bytes'] for s in samples),
                    sampled_peak_physical_bytes=max(s['physical_bytes'] for s in samples),
                    partial=partial, final=final, nonprotocol=nonprotocol, samples=samples)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', action='store_true', help='Requires prior GPU coordination')
    parser.add_argument('--output', type=Path, default=HERE/'startup-results')
    args = parser.parse_args()
    # Do not start an inference process merely to inspect this script.
    if not args.run:
        print('Prepared only. Explicit --run required after GPU handoff.')
        return
    args.output.mkdir(exist_ok=False)
    plan = [(arm, CASES[0]) for arm in ['old', 'new', 'new', 'old']]
    plan += [(arm, CASES[1]) for arm in ['new', 'old', 'old', 'new']]
    rows = []
    for index, (arm, item) in enumerate(plan):
        row = run(arm, item, index, args.output)
        rows.append(row)
        (args.output/'raw.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2)+'\n')
        print(json.dumps({k: row[k] for k in ['arm', 'input', 'startup_ready_s',
                         'first_pcm_to_visible_s', 'startup_to_visible_s']}, ensure_ascii=False), flush=True)
    parity = all(len({r['partial']['text'] for r in rows if r['input'] == item['id']}) == 1
                 for item in CASES[:2])
    metrics = ['startup_ready_s', 'first_pcm_to_visible_s', 'startup_to_visible_s',
               'sampled_peak_resident_bytes', 'sampled_peak_physical_bytes']
    summary = dict(basis=BASIS, scope='Fresh helper process startup with OS file cache uncontrolled; '
                   'fixed 0.8 s public PCM, not native UI or microphone acceptance; '
                   '20 ms sampled memory can miss shorter peaks. Same toolchain/control source, '
                   'no token math changes. No production package modified.',
                   order=[arm for arm, _ in plan], prefix_text_equal=parity,
                   medians={arm: {key: statistics.median(r[key] for r in rows if r['arm']==arm)
                                  for key in metrics} for arm in ['old', 'new']},
                   cpu_at_ready_medians={arm: statistics.median(r['ready_usage']['cpu_s']
                                         for r in rows if r['arm']==arm) for arm in ['old', 'new']},
                   cpu_at_first_text_medians={arm: statistics.median(r['first_usage']['cpu_s']
                                              for r in rows if r['arm']==arm) for arm in ['old', 'new']})
    (args.output/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n')
    assert parity
    print(json.dumps(summary, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
