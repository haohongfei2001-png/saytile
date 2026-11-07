#!/usr/bin/env python3
"""Verify the offline candidate and fail-closed CLI cases without identity or network access."""
import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('saytile_distribution', HERE / 'developer-id.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
real_run = subprocess.run
allowed = {'xcrun': {'--find'}, 'hdiutil': {'verify', 'attach', 'detach'},
           'codesign': {'--verify'}, 'lipo': {'-archs'}, 'ditto': {'--norsrc'}}
observed = []


def offline_run(command, *args, **kwargs):
    name, action = Path(command[0]).name, command[1]
    if action not in allowed.get(name, set()) or (name == 'hdiutil' and action == 'attach' and '-readonly' not in command):
        raise RuntimeError(f'Unexpected subprocess in offline verification: {name} {action}')
    observed.append([name, action])
    return real_run(command, *args, **kwargs)


def case(arguments, expected=None):
    stream = io.StringIO()
    with patch.object(sys, 'argv', ['developer-id.py', *map(str, arguments)]), \
         patch.object(subprocess, 'run', offline_run), contextlib.redirect_stdout(stream):
        try:
            release.main()
        except (ValueError, OSError) as error:
            if expected and expected in str(error):
                return 'REJECTED'
            raise
    if expected:
        raise RuntimeError(f'Expected refusal containing {expected}')
    return json.loads(stream.getvalue())


result = {'candidate': case(['preflight'])}
with tempfile.TemporaryDirectory(prefix='saytile-distribution-test-') as raw:
    temp = Path(raw)
    bad = temp / 'synthetic.dmg'
    bad.write_bytes(b'synthetic non-candidate fixture')
    result['wrong_candidate'] = case(['preflight', '--candidate', bad], 'SHA-256 mismatch')
    work = temp / 'never-created'
    fake = ['submit', '--work', work, '--team', '0000000000', '--profile', 'unused-test-name']
    result['ad_hoc_identity'] = case(fake + ['--identity', '-'], 'exact Developer ID')
    result['empty_profile'] = case(['submit', '--identity', '0' * 40, '--team', '0000000000', '--work', work, '--profile', ''], 'profile name')
    if work.exists():
        raise RuntimeError('Invalid signing arguments created a work directory')
    finish = ['finish', '--work', work, '--profile', 'unused-test-name', '--output']
    result['existing_output'] = case(finish + [bad], 'new DMG path')
    result['app_bundle_destination'] = case(finish + [temp / 'fixture.app/output.dmg'], 'application bundle')
    if bad.read_bytes() != b'synthetic non-candidate fixture':
        raise RuntimeError('Refusal modified existing output')
result['observed_offline_tools'] = observed
result['real_signing'] = 'NOT_RUN'
result['real_notarization'] = 'NOT_RUN'
result['public_distribution'] = 'PENDING'
print(json.dumps(result, indent=2))
