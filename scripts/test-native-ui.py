#!/usr/bin/env python3
"""Render production SwiftUI windows using synthetic data; optional native AX control actions.
Never activates a window, requests permission, records audio, or queries another app's UI.
"""
import argparse, hashlib, json, os, pathlib, plistlib, struct, subprocess, tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--app', required=True, type=pathlib.Path)
parser.add_argument('--output', default='evidence/rc/ui', type=pathlib.Path)
parser.add_argument('--controls', action='store_true', help='Use existing AX permission only; no prompt')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
app = args.app.resolve()
binary = app / 'Contents/MacOS/Saytile'
output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
with tempfile.TemporaryDirectory(prefix='saytile-native-ui-') as temp:
    directory = pathlib.Path(temp)
    environment = dict(os.environ)
    if args.controls:
        helper = directory / 'ui-control-probe'
        subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', str(root / 'tests/fixtures/NativeUIControlProbe.swift'), '-o', str(helper)], check=True)
        environment['SAYTILE_UI_CONTROL_PROBE'] = str(helper)
    result = subprocess.run([str(binary), '--data-directory', str(directory / 'data'), '--ui-review', str(output)], capture_output=True, text=True, timeout=180, env=environment)
    log = result.stdout + result.stderr
    (output / 'run.log').write_text(log)
    passed = result.returncode == 0 and 'UI_REVIEW_PASS' in log
    if args.controls:
        passed = passed and log.count('NATIVE_UI_AXPRESS ') == 39 and log.count('NATIVE_UI_MENU_SELECT ') == 6 and log.count('NATIVE_UI_INSPECT ') == 5 and log.count('NATIVE_UI_AXSETVALUE ') == 6 and log.count('NATIVE_UI_FIELD_EDIT ') == 6 and log.count('NATIVE_UI_SECURE_FIELD_EDIT ') == 3 and log.count('UI_CONTROL_PASS ') == 12
    files = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.glob('*.png'))}
    geometries = [json.loads(line[len('UI_IMAGE_GEOMETRY '):]) for line in log.splitlines() if line.startswith('UI_IMAGE_GEOMETRY ')]
    panel_dimensions = {item['name'] + '.png': item for item in geometries if item['name'].startswith('panel-')}
    panel_images = sorted(output.glob('panel-*.png'))
    valid_geometry = len(panel_dimensions) == len(panel_images) and all(
        320 <= item['width_points'] <= 360 and 200 <= item['height_points'] <= 480
        and struct.unpack('>II', (output / name).read_bytes()[16:24]) == (item['width_pixels'], item['height_pixels'])
        for name, item in panel_dimensions.items())
    passed = passed and len(files) == (31 if args.controls else 20) and valid_geometry and log.count('UI_NATIVE_TEXT_PASS ') == 1 and log.count('UI_NATIVE_UNICODE_PASS ') == 1
    (output / 'manifest.json').write_text(json.dumps({'passed': passed, 'controls_requested': args.controls, 'source_revision': metadata.get('SaytileSourceRevision'), 'source_dirty': metadata.get('SaytileSourceDirty'), 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'images': files, 'panel_dimensions': panel_dimensions, 'outside_foreground_observations': log.count('UI_FOREGROUND_OBSERVATION '), 'native_ax_press': log.count('NATIVE_UI_AXPRESS '), 'native_menu_select': log.count('NATIVE_UI_MENU_SELECT '), 'native_control_inspections': log.count('NATIVE_UI_INSPECT '), 'native_text_checks': log.count('UI_NATIVE_TEXT_PASS '), 'native_unicode_checks': log.count('UI_NATIVE_UNICODE_PASS '), 'native_ax_set_value': log.count('NATIVE_UI_AXSETVALUE '), 'native_field_edits': log.count('NATIVE_UI_FIELD_EDIT '), 'native_secure_field_edits': log.count('NATIVE_UI_SECURE_FIELD_EDIT '), 'control_groups': log.count('UI_CONTROL_PASS '), 'scope': 'Production SwiftUI and NSTextView in transparent nonactivating AppKit windows; fixture PID only; synthetic data; native selection/scroll checks use owned AppKit controls and Store updates; capture actions and first-connection credentials/verification are injected; TEST_ONLY live-shaped receipt is controller evidence only; first-connection and compact-panel fixtures use no Keychain; preceding settings render performs scoped metadata presence only, no credential reads; no provider/network/microphone/global keys/clipboard write/external target; candidate activation rejected; outside foreground transitions recorded without causal claims'}, ensure_ascii=False, indent=2) + '\n')
    print(log)
    raise SystemExit(0 if passed else 1)
