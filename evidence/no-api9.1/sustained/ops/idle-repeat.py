"""Run one uninterrupted repeat with the frozen App in a new, empty data directory."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sustained = Path(__file__).resolve().parents[1]
root = sustained.parents[2]
observation = sys.argv[2] if len(sys.argv) == 3 else 'idle-repeat'
if observation not in ('idle-repeat', 'idle-fd-fixed'):
    raise ValueError('Unknown observation directory')
out = sustained / observation
identity = json.loads((sustained.parent / 'app/identity.json').read_text())
wake = Path(sys.argv[1]).resolve()
expected_wake = json.loads((sustained / 'wake-identity.json').read_text())['probe_sha256']
if hashlib.sha256(wake.read_bytes()).hexdigest() != expected_wake:
    raise ValueError('Wake probe integrity mismatch')

def main():
    out.mkdir(exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='saytile-idle91-repeat-') as temp:
        work = Path(temp)
        resource = work / 'resource-observer'
        subprocess.run(['/usr/bin/clang', '-O2', '-Wall', '-Wextra', '-Werror',
                        sustained / 'ResourceObserver.c', '-o', resource], check=True)
        producer = subprocess.Popen([sys.executable, sustained / 'soak.py',
                                     out / 'soak', identity['app_path']], cwd=root)
        interval = out / 'soak/interval.json'
        for _ in range(120):
            if interval.exists():
                break
            if producer.poll() is not None:
                raise RuntimeError('No startup receipt from the repeat')
            time.sleep(0.5)
        manifest = json.loads(interval.read_text())
        assert manifest['source'] == identity['source_revision']
        assert manifest['binary_sha256'] == identity['binary_sha256']
        deadline = datetime.datetime.fromisoformat(manifest['due_utc']).timestamp()
        (out / 'observers.json').write_text(json.dumps({
            'source': manifest['source'], 'pid': manifest['pid'],
            'wake_probe_sha256': expected_wake,
            'soak_script_sha256': hashlib.sha256((sustained / 'soak.py').read_bytes()).hexdigest(),
            'resource_observer_sha256': hashlib.sha256(resource.read_bytes()).hexdigest(),
            'duration_seconds': 72 * 3600, 'scope': 'Fresh uninterrupted run, no credited time from the previous PID.'
        }, indent=2) + '\n')
        with (out / 'process-resource.jsonl').open('x') as log:
            kernel = subprocess.Popen([resource, str(manifest['pid']), str(int(deadline))], stdout=log)
            passive = subprocess.Popen([wake, 'passive', work / 'wake-store', out / 'passive-wake.jsonl',
                                        str(manifest['pid']), str(deadline)])
            try:
                status = producer.wait()
                kernel_status = kernel.wait(timeout=120)
                wake_status = passive.wait(timeout=120)
            finally:
                for proc in (producer, kernel, passive):
                    if proc.poll() is None:
                        proc.terminate()
                        proc.wait(timeout=30)
        (out / 'exit.json').write_text(json.dumps({
            'soak': status, 'resource': kernel_status, 'wake': wake_status,
            'source': manifest['source'], 'end_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()
        }, indent=2) + '\n')
        phase = '72h' if not any((status, kernel_status, wake_status)) else ('fd-interrupted' if observation == 'idle-fd-fixed' else 'repeat-interrupted')
        subprocess.run([sys.executable, sustained / 'ops/finish-observations.py', phase], cwd=root, check=True)

if __name__ == '__main__':
    main()
