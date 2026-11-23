#!/usr/bin/env python3
"""Exercise the actual app CLI without audio, credentials, prompts or cloud calls."""
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile


def check(app):
    if not __debug__:
        raise RuntimeError('Run isolation checks without Python optimization; assertions are required')
    rows = []
    # Refuse to run production-path rejection cases against an older unguarded
    # executable. This inspects only the candidate binary, never an archive.
    binary = app.read_bytes()
    if any(marker not in binary for marker in [b'DIAGNOSTICS_REJECTED_DATA_DIRECTORY',
                                               b'DIAGNOSTICS_REQUIRE_SEPARATE_DATA_DIRECTORY_ARGUMENT',
                                               b'RETIRED_PROBE_USE_SINGLE_ASR_WITH_ISOLATED_DIRECTORY']):
        raise RuntimeError('Candidate lacks early directory guard; no process was launched')
    result = subprocess.run([str(app), '--data-directory=/synthetic/explicit-directory'],
                            capture_output=True, text=True, timeout=15)
    if result.returncode != 64 or 'DIAGNOSTICS_REQUIRE_SEPARATE_DATA_DIRECTORY_ARGUMENT' not in result.stdout:
        raise RuntimeError('Unsupported directory spelling was not rejected')
    rows.append({'case': 'equals_directory_syntax_rejected', 'exit': 64,
                 'result': 'PASS_BEFORE_STORE_CONSTRUCTION'})
    for name, args in [
        ('missing_directory', ['--single-asr-probe', '/synthetic/absent.wav']),
        ('missing_value', ['--single-asr-probe', '/synthetic/absent.wav', '--data-directory']),
        ('flag_as_value', ['--single-asr-probe', '/synthetic/absent.wav', '--data-directory', '--report-dir', '/synthetic/no-output']),
    ]:
        result = subprocess.run([str(app)] + args, capture_output=True, text=True, timeout=15)
        assert result.returncode == 64, (name, result.returncode, result.stdout, result.stderr)
        assert 'DIAGNOSTICS_REQUIRE_EXPLICIT_ISOLATED_DATA_DIRECTORY' in result.stdout
        rows.append({'case': name, 'exit': result.returncode, 'result': 'PASS_BEFORE_STORE_CONSTRUCTION'})
    retired = subprocess.run([str(app), '--multi-asr-probe', '/synthetic/absent.wav'],
                             capture_output=True, text=True, timeout=15)
    assert retired.returncode == 64 and 'RETIRED_PROBE_USE_SINGLE_ASR' in retired.stdout
    rows.append({'case': 'retired_probe_rejected_before_store', 'exit': 64, 'result': 'PASS_BEFORE_STORE_CONSTRUCTION'})
    production = Path.home() / 'Library/Application Support/Saytile'
    modes = [('--smoke-test', []), ('--device-probe', []), ('--audio-probe', ['/synthetic/absent.wav']),
             ('--single-asr-probe', ['/synthetic/absent.wav']), ('--render-preview', []),
             ('--focus-probe', []), ('--ui-review', ['/synthetic/no-output']),
             ('--connection-setup', []), ('explicit_directory', [])]
    for mode, operands in modes:
        arguments = [] if mode == 'explicit_directory' else [mode, *operands]
        result = subprocess.run([str(app), '--data-directory', str(production), *arguments],
                                capture_output=True, text=True, timeout=15)
        assert result.returncode == 64 and 'DIAGNOSTICS_REJECTED_DATA_DIRECTORY' in result.stdout, mode
        rows.append({'case': 'production_rejected_' + mode.removeprefix('--'), 'exit': 64,
                     'result': 'PASS_BEFORE_STORE_CONSTRUCTION'})
    with tempfile.TemporaryDirectory(prefix='saytile-production-alias-probe-') as temporary:
        alias = Path(temporary) / 'alias'
        alias.symlink_to(production, target_is_directory=True)
        for name, directory in [('production_child', production / 'Audio' / 'no-api-test-must-not-exist'),
                                ('production_case_alias', production.with_name('sAyTiLe')),
                                ('production_parent_alias', alias / 'never-created-fixture-leaf')]:
            result = subprocess.run([str(app), '--data-directory', str(directory), '--smoke-test'],
                                    capture_output=True, text=True, timeout=15)
            assert result.returncode == 64 and 'DIAGNOSTICS_REJECTED_DATA_DIRECTORY' in result.stdout, name
            rows.append({'case': name, 'exit': 64, 'result': 'PASS_BEFORE_STORE_CONSTRUCTION'})
    repository = Path(__file__).resolve().parents[4]
    configuration = repository / 'research/asr/benchmark/quality-evaluation/prepared-24/configurations/C_dual.json'
    config = json.loads(configuration.read_text())
    assert config['cloudEnabled'] is False and all(not item['cloudConsent'] for item in config['models'])
    with tempfile.TemporaryDirectory(prefix='saytile-cloud-disabled-probe-') as directory:
        result = subprocess.run([str(app), '--data-directory', directory, '--single-asr-probe', '/synthetic/absent.wav',
            '--recognition-config', str(configuration), '--report-dir', directory + '/report'],
            capture_output=True, text=True, timeout=20)
        assert result.returncode == 1, (result.returncode, result.stdout, result.stderr)
        assert 'SINGLE_ASR_PROBE_FAILED' in result.stdout
        connection = sqlite3.connect(directory + '/Saytile.sqlite')
        try:
            records = connection.execute('SELECT count(*) FROM recordings').fetchone()[0]
            runs = connection.execute('SELECT count(*) FROM model_runs').fetchone()[0]
        finally:
            connection.close()
        assert records == runs == 0
        rows.append({'case': 'explicit_isolated_directory_cloud_disabled', 'exit': result.returncode,
            'recordings': records, 'model_runs': runs, 'result': 'PASS_NO_FIXTURE_IMPORTED_NO_PROVIDER_STARTED'})
    return {'cases': rows, 'microphone_started': False, 'cloud_calls': 0, 'private_database_accessed': False,
        'scope_note': 'Directory guards are before Store construction; no user store was inspected to check absence of changes.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, required=True, help='Exact candidate executable, not bundle directory')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = check(args.app.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f"CLI_PROBE_ISOLATION_PASS {len(result['cases'])} cases; no microphone, corpus read, credentials or network calls")
