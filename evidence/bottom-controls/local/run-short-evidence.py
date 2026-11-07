#!/usr/bin/env python3
"""Run the existing storage, VAD and conversion probes against one frozen checkout."""
import hashlib
import json
import os
import pathlib
import re
import subprocess
import time


OUT = pathlib.Path(__file__).resolve().parent
ROOT = OUT.parents[2]
SOURCE_DIRECTORIES = ['Sources', 'scripts', 'tests', 'packaging']
RECIPES = ['run-short-evidence.py', 'run-conversion-reference.sh', 'run-realtime-evidence.py', 'finalize-realtime-evidence.py']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text())


def write_json(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + '\n')


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=ROOT, text=True).strip()


def source_hashes():
    files = [ROOT / 'Package.swift']
    for directory in SOURCE_DIRECTORIES:
        files.extend(path for path in (ROOT / directory).rglob('*')
                     if path.is_file() and '.DS_Store' not in path.name)
    return {str(path.relative_to(ROOT)): sha(path) for path in sorted(files)}


def run(command, env, log, error_log=None):
    print('Running', command[0], command[1], flush=True)
    with (OUT / log).open('w') as stdout:
        if error_log:
            with (OUT / error_log).open('w') as stderr:
                subprocess.run(command, cwd=ROOT, env=env, stdout=stdout, stderr=stderr, check=True)
        else:
            subprocess.run(command, cwd=ROOT, env=env, stdout=stdout, stderr=subprocess.STDOUT, check=True)


def main():
    revision = os.environ['SAYTILE_FROZEN_SHA']
    tree = os.environ['SAYTILE_FROZEN_TREE']
    if not __debug__ or not all(re.fullmatch(r'[0-9a-f]{40}', value) for value in [revision, tree]):
        raise SystemExit('Supply the full frozen revision and tree and use normal Python execution')
    if git('rev-parse', 'HEAD') != revision or git('rev-parse', 'HEAD^{tree}') != tree:
        raise SystemExit('Frozen source identity mismatch')
    if git('status', '--porcelain', '--', *SOURCE_DIRECTORIES, 'Package.swift'):
        raise SystemExit('The source, packaging or tests contain changes outside the frozen revision')
    if (OUT / 'short-source-before.json').exists():
        raise SystemExit('Existing short-run receipts in this directory must be preserved')

    fixture = read_json(OUT / 'input-fixture.json')
    asset = ROOT / fixture['repository_path']
    if sha(asset) != fixture['sha256']:
        raise SystemExit('Synthetic input hash mismatch')
    fixture['path'] = str(asset)
    write_json('input-fixture.json', fixture)
    before = source_hashes()
    recipe_hashes = {name: sha(OUT / name) for name in RECIPES}
    write_json('short-source-before.json', {
        'source_revision': revision, 'tree': tree, 'unix_started': time.time(),
        'source_sha256': before, 'input_sha256': fixture['sha256'], 'validation_sha256': recipe_hashes})

    prefix = pathlib.Path('/tmp') / ('saytile-no-api6-' + revision[:12])
    static = pathlib.Path(str(prefix) + '-static')
    env = dict(os.environ, SAYTILE_BUFFER_SCRATCH=str(static), SAYTILE_STORAGE_SCRATCH=str(static),
               SAYTILE_STORAGE_OUTPUT=str(OUT / 'storage-scale'))
    try:
        run(['bash', 'scripts/test-audio-buffer-memory.sh'], env, 'voice-buffer.json', 'voice-buffer-build-resources.log')
        run(['python3', 'scripts/test-rc-storage-processes.py', '--output', str(OUT / 'storage-processes.json')], env, 'storage-processes.log')
        run(['bash', 'scripts/test-rc-storage-scale.sh'], env, 'storage-scale-run.log')
        run(['bash', str(OUT / 'run-conversion-reference.sh')], env, 'conversion-reference-build.log')
    except subprocess.CalledProcessError as error:
        write_json('short-run-error.json', {'command': error.cmd, 'exit': error.returncode,
                   'source_revision': git('rev-parse', 'HEAD'), 'unix_finished': time.time()})
        raise

    paths = {'voice_buffer': static / 'buffer-probe', 'storage_scale': static / 'scale-probe',
             'storage_process': static / 'probe', 'released_beta': static / 'beta-probe',
             'released_rc1': static / 'rc1-probe', 'conversion_reference': pathlib.Path(str(prefix) + '-reference-probe')}
    probes = {name: {'path': str(path), 'sha256': sha(path)} for name, path in paths.items()}
    write_json('probe-binaries.json', {'source_revision': revision, 'probes': probes})
    after = source_hashes()
    changed = sorted(path for path in set(before) | set(after) if before.get(path) != after.get(path))
    store = read_json(OUT / 'storage-processes.json')
    scale = read_json(OUT / 'storage-scale/storage-scale.json')
    vad = read_json(OUT / 'voice-buffer.json')
    reference = read_json(OUT / 'conversion-reference.json')
    checks = {
        'source_head_and_tree_match': git('rev-parse', 'HEAD') == revision and git('rev-parse', 'HEAD^{tree}') == tree,
        'unchanged_source_files': not changed,
        'unchanged_validation_recipes': all(sha(OUT / name) == digest for name, digest in recipe_hashes.items()),
        'unchanged_input': sha(asset) == fixture['sha256'],
        'native_process_checks': store['status'] == 'PASS' and store['passed'] == 12 and store['probe_sha256'] == probes['storage_process']['sha256'],
        'scale': scale['schema'] == 5 and scale['recordings'] == 100000 and scale['revisions'] == 300000 and scale['search_matches'] == 100 and scale['recovery_found'],
        'vad': vad['status'] == 'PASS',
        'independent_reference': reference['status'] == 'PASS' and reference['source_revision'] == revision and reference['all_source_batches_supplied'] and reference['output_frames'] == 28800000 and reference['reference_probe_sha256'] == probes['conversion_reference']['sha256'],
    }
    status = 'PASS' if all(checks.values()) else 'FAIL'
    write_json('short-source-after.json', {'source_revision': revision, 'tree': tree, 'source_changed': changed,
               'source_sha256': after, 'unix_finished': time.time(), 'input_sha256': sha(asset), 'checks': checks, 'validation_sha256': recipe_hashes,
               'status': status, 'wallclock_soak_status': 'PREPARED_NOT_STARTED_WAITING_FOR_ROOT'})
    print('Short checks', status, flush=True)
    return 0 if status == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
