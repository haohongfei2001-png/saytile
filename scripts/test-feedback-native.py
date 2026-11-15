#!/usr/bin/env python3
"""Exercise shipping feedback settings via owned native AX controls and synthetic data.
No installed app, microphone, user defaults, clipboard or remote provider is used.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
app = args.app.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
binary = app / 'Contents/MacOS/Saytile'
metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if not metadata.get('SaytileSourceRevision') or metadata.get('SaytileSourceDirty') is not False:
    raise SystemExit('Requires a clean, source-bound app candidate')
with tempfile.TemporaryDirectory(prefix='saytile-feedback-native-') as temp:
    folder = Path(temp)
    helper = folder / 'ui-control-probe'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-module-cache-path', str(folder / 'modules'),
                    str(root / 'tests/fixtures/NativeUIControlProbe.swift'), '-o', str(helper)], check=True)
    env = dict(os.environ, SAYTILE_FEEDBACK_REVIEW='1', SAYTILE_UI_CONTROL_PROBE=str(helper),
               SAYTILE_FEEDBACK_REVIEW_STATE=str(folder / 'feedback-state'))
    result = subprocess.run([str(binary), '--data-directory', str(folder / 'data'),
                             '--ui-review', str(output)], capture_output=True, text=True, env=env, timeout=180)
    log = result.stdout + result.stderr
    reopened = None
    if result.returncode == 0:
        env['SAYTILE_FEEDBACK_REVIEW_PHASE'] = 'reopen'
        reopened = subprocess.run([str(binary), '--data-directory', str(folder / 'data'),
                                   '--ui-review', str(output)], capture_output=True, text=True, env=env, timeout=60)
        log += reopened.stdout + reopened.stderr
    (output / 'run.log').write_text(log)
    image_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.glob('*.png'))}
    expected = {'feedback-empty.png', 'feedback-draft.png', 'feedback-received.png',
                'feedback-delivered.png', 'feedback-deleted.png', 'timeline-feedback-controls.png',
                'timeline-feedback-settings.png'}
    checks = {
        'native_process_completed': result.returncode == 0 and reopened is not None and reopened.returncode == 0,
        'native_send_withdraw': log.count('FEEDBACK_NATIVE_PASS ') == 1,
        'reopen_draft_and_record': log.count('FEEDBACK_RESTART_PASS ') == 1,
        'offline_immutable_retry': log.count('FEEDBACK_OFFLINE_PASS ') == 1,
        'no_external_submission': log.count('FEEDBACK_REVIEW_PASS ') == 1,
        'real_send_action': log.count('NATIVE_UI_AXPRESS feedback.send ') == 1,
        'native_unicode_editor': log.count('FEEDBACK_NATIVE_TEXT ') == 1,
        'all_native_snapshots': set(image_hashes) == expected,
        'no_candidate_activation': 'candidate activated during' not in log and log.count('UI_CAPTURE ') == 2 and log.count('candidate_activated=false') == 2,
    }
    receipt = {'status': 'PASS' if all(checks.values()) else 'FAIL', 'checks': checks,
               'source': metadata['SaytileSourceRevision'], 'source_dirty': metadata['SaytileSourceDirty'],
               'version': metadata.get('CFBundleShortVersionString'), 'build': metadata.get('CFBundleVersion'),
               'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'images': image_hashes,
               'scope': 'Production FeedbackSettings component in an owned nonactivating native window; '
                        'NSTextView insertText/delegate input and AXPress Send/refresh/withdraw. Actual SQLite outbox, '
                        'immutable retry and draft restart; injected transport and synthetic capabilities. Two separate process launches exercise persisted restart. '
                        'No live service, private archive, Keychain, microphone or global clipboard accessed. '
                        'Component interactions plus production SettingsView screenshot and selected feedback-page AX inspection; remote delivery is separate acceptance.'}
    (output / 'receipt.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    print(log)
    print(receipt['status'], json.dumps(checks))
    raise SystemExit(0 if all(checks.values()) else 1)
