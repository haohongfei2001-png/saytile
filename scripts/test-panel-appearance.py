#!/usr/bin/env python3
"""Exercise shipping appearance settings via owned native AX controls and synthetic data.
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
with tempfile.TemporaryDirectory(prefix='saytile-appearance-native-') as temp:
    folder = Path(temp)
    helper = folder / 'ui-control-probe'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-module-cache-path', str(folder / 'modules'),
                    str(root / 'tests/fixtures/NativeUIControlProbe.swift'), '-o', str(helper)], check=True)
    env = dict(os.environ, SAYTILE_APPEARANCE_REVIEW='1', SAYTILE_UI_CONTROL_PROBE=str(helper))
    result = subprocess.run([str(binary), '--data-directory', str(folder / 'data'),
                             '--ui-review', str(output)], capture_output=True, text=True, env=env, timeout=180)
    log = result.stdout + result.stderr
    (output / 'run.log').write_text(log)
    image_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.glob('*.png'))}
    expected = {'appearance-default.png', 'appearance-opacity-mist.png', 'appearance-opacity-dense.png',
                'appearance-opacity-opaque.png', 'appearance-blue.png', 'appearance-warm-graphite.png',
                'appearance-type-small.png', 'appearance-type-large.png', 'appearance-type-extraLarge.png',
                'appearance-no-border.png', 'appearance-restored.png', 'appearance-settings-default.png',
                'appearance-brand-black.png', 'appearance-brand-purple.png',
                'appearance-brand-black-settings.png', 'appearance-brand-purple-settings.png',
                'appearance-settings-custom.png', 'appearance-settings-restored.png',
                'timeline-appearance-panel.png', 'timeline-appearance-settings.png'}
    checks = {
        'native_process_completed': result.returncode == 0,
        'appearance_contract': log.count('APPEARANCE_REVIEW_PASS ') == 1,
        'real_menu_selections': log.count('NATIVE_APPEARANCE_MENU ') == 11,
        'border_action': log.count('NATIVE_UI_AXPRESS settings.panelBorder ') == 1,
        'brand_round_trip_actions': log.count('NATIVE_UI_AXPRESS 黑色 ') == 1 and log.count('NATIVE_UI_AXPRESS 原紫色 ') == 1,
        'apply_size_action': log.count('NATIVE_UI_AXPRESS settings.applyPanelSize ') == 1,
        'reset_action': log.count('NATIVE_UI_AXPRESS settings.resetAppearance ') == 1,
        'all_native_snapshots': set(image_hashes) == expected,
        'no_candidate_activation': 'candidate activated during' not in log and log.count('candidate_activated=false') == 2,
    }
    receipt = {'status': 'PASS' if all(checks.values()) else 'FAIL', 'checks': checks,
               'source': metadata['SaytileSourceRevision'], 'source_dirty': metadata['SaytileSourceDirty'],
               'version': metadata.get('CFBundleShortVersionString'), 'build': metadata.get('CFBundleVersion'),
               'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'images': image_hashes,
               'scope': 'Production SettingsView/InputPanelWindowView in owned nonactivating native windows; '
                        '11 picker selections through AXPress and AppKit menu actions; resets, border, font and edit/selection '
                        'protection; synthetic capture boundary with zero starts and zero cloud calls. Size picker and apply '
                        'button action only; actual AppDelegate window resizing is a separate acceptance. Images use AppKit '
                        'cacheDisplay; backdrop blur composition is separately covered by scripts/test-product-windows.py.'}
    (output / 'receipt.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    print(log)
    print(receipt['status'], json.dumps(checks))
    raise SystemExit(0 if all(checks.values()) else 1)
