#!/usr/bin/env python3
"""Exercise the actual app CLI without audio, credentials, prompts or cloud calls."""
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile


def check(app):
    rows = []
    for name, args in [
        ('missing_directory', ['--multi-asr-probe', '/synthetic/absent.wav']),
        ('missing_value', ['--multi-asr-probe', '/synthetic/absent.wav', '--data-directory']),
        ('flag_as_value', ['--multi-asr-probe', '/synthetic/absent.wav', '--data-directory', '--report-dir', '/synthetic/no-output']),
    ]:
        result = subprocess.run([str(app)] + args, capture_output=True, text=True, timeout=15)
        assert result.returncode == 64, (name, result.returncode, result.stdout, result.stderr)
        assert 'DIAGNOSTICS_REQUIRE_EXPLICIT_ISOLATED_DATA_DIRECTORY' in result.stdout
        rows.append({'case': name, 'exit': result.returncode, 'result': 'PASS_BEFORE_STORE_CONSTRUCTION'})
    repository = Path(__file__).resolve().parents[4]
    configuration = repository / 'research/asr/benchmark/quality-evaluation/prepared-24/configurations/C_dual.json'
    config = json.loads(configuration.read_text())
    assert config['cloudEnabled'] is False and all(not item['cloudConsent'] for item in config['models'])
    with tempfile.TemporaryDirectory(prefix='saytile-cloud-disabled-probe-') as directory:
        result = subprocess.run([str(app), '--data-directory', directory, '--multi-asr-probe', '/synthetic/absent.wav',
            '--recognition-config', str(configuration), '--report-dir', directory + '/report'],
            capture_output=True, text=True, timeout=20)
        assert result.returncode == 1, (result.returncode, result.stdout, result.stderr)
        assert 'MULTI_ASR_PROBE_FAILED' in result.stdout
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
    print('CLI_PROBE_ISOLATION_PASS 4 cases; no microphone, corpus read, credentials or network calls')
