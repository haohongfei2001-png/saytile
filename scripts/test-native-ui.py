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
        expected_secure = {'recognition.model.a71e0001-0000-4000-8000-000000000001.secret',
                           'recognition.model.a71e0001-0000-4000-8000-000000000004.secret'}
        secure_edits = [line.split()[1] for line in log.splitlines() if line.startswith('NATIVE_UI_SECURE_FIELD_EDIT ')]
        passed = passed and sorted(secure_edits) == sorted(expected_secure)
        passed = passed and log.count('NATIVE_UI_AXPRESS ') == 41 and log.count('NATIVE_UI_MENU_SELECT ') == 10 and log.count('NATIVE_UI_INSPECT ') == 0 and log.count('NATIVE_UI_PANEL_INSPECT ') == 11 and log.count('UI_BOTTOM_CONTROLS_PASS ') == 11 and log.count('NATIVE_UI_AXSETVALUE ') == 5 and log.count('NATIVE_UI_FIELD_EDIT ') == 5 and log.count('NATIVE_UI_SECURE_FIELD_EDIT ') == 2 and log.count('UI_CONTROL_PASS ') == 15 and log.count('UI_NATIVE_CAPTURE_ACK ') == 1 and log.count('UI_EMPTY_PANEL_MENU_PASS ') == 1 and log.count('UI_PRIVATE_COPY_PASS ') == 2 and log.count('UI_VAD_END_PASS ') == 1 and log.count('NATIVE_UI_CONTEXT_ITEMS ') == 10
    files = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.glob('*.png'))}
    geometries = [json.loads(line[len('UI_IMAGE_GEOMETRY '):]) for line in log.splitlines() if line.startswith('UI_IMAGE_GEOMETRY ')]
    panel_dimensions = {item['name'] + '.png': item for item in geometries if item['name'].startswith('panel-')}
    panel_images = sorted(output.glob('panel-*.png'))
    valid_geometry = len(panel_dimensions) == len(panel_images) and all(
        320 <= item['width_points'] <= 360 and 200 <= item['height_points'] <= 480
        and struct.unpack('>II', (output / name).read_bytes()[16:24]) == (item['width_pixels'], item['height_pixels'])
        for name, item in panel_dimensions.items())
    keyboard_checks = {phase: log.count('UI_KEYBOARD_ISOLATION ' + phase + ' can_become_key=false can_become_main=false is_key=false is_main=false')
                       for phase in ['before-validation', 'after-validation', 'after-interaction', 'capture', 'before-field-edit', 'after-field-edit']}
    valid_keyboard_isolation = keyboard_checks['capture'] == len(files) + 3 and keyboard_checks['before-validation'] > 0 \
        and keyboard_checks['before-validation'] == keyboard_checks['after-validation'] == keyboard_checks['after-interaction'] \
        and keyboard_checks['before-field-edit'] == keyboard_checks['after-field-edit'] == (5 if args.controls else 0)
    passed = passed and "settings-hosted.png" in files and len(files) == (38 if args.controls else 28) and valid_geometry and valid_keyboard_isolation and log.count('UI_NATIVE_TEXT_PASS ') == 1 and log.count('UI_NATIVE_UNICODE_PASS ') == 1 and log.count('UI_NATIVE_NEAR_BOTTOM_PASS ') == 1
    passed = passed and (args.controls or log.count('UI_SYNTHETIC_CAPTURE_STATES_PASS ') == 1)
    passed = passed and log.count('UI_VOICE_GLYPH_PASS ') == 1
    reference_files = [output / 'approved-reference' / ('reference-' + state + '.png') for state in ('paused', 'standby', 'recognizing')]
    passed = passed and all(p.exists() for p in reference_files) and log.count('REFERENCE_GEOMETRY ') == 3
    (output / 'manifest.json').write_text(json.dumps({'passed': passed, 'controls_requested': args.controls, 'source_revision': metadata.get('SaytileSourceRevision'), 'source_dirty': metadata.get('SaytileSourceDirty'), 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'images': files, 'panel_dimensions': panel_dimensions, 'keyboard_isolation_checks': keyboard_checks, 'outside_foreground_observations': log.count('UI_FOREGROUND_OBSERVATION '), 'native_ax_press': log.count('NATIVE_UI_AXPRESS '), 'native_menu_select': log.count('NATIVE_UI_MENU_SELECT '), 'native_control_inspections': log.count('NATIVE_UI_INSPECT '), 'native_panel_inspections': log.count('NATIVE_UI_PANEL_INSPECT '), 'bottom_control_checks': log.count('UI_BOTTOM_CONTROLS_PASS '), 'synthetic_voice_state_scenarios': log.count('UI_SYNTHETIC_CAPTURE_STATES_PASS '), 'empty_panel_menu_checks': log.count('UI_EMPTY_PANEL_MENU_PASS '), 'private_copy_checks': log.count('UI_PRIVATE_COPY_PASS '), 'vad_end_and_late_result_checks': log.count('UI_VAD_END_PASS '), 'context_menu_inventories': log.count('NATIVE_UI_CONTEXT_ITEMS '), 'capture_resume_acknowledgements': log.count('UI_NATIVE_CAPTURE_ACK '), 'native_text_checks': log.count('UI_NATIVE_TEXT_PASS '), 'native_unicode_checks': log.count('UI_NATIVE_UNICODE_PASS '), 'native_near_bottom_checks': log.count('UI_NATIVE_NEAR_BOTTOM_PASS '), 'native_ax_set_value': log.count('NATIVE_UI_AXSETVALUE '), 'native_field_edits': log.count('NATIVE_UI_FIELD_EDIT '), 'native_secure_field_edits': log.count('NATIVE_UI_SECURE_FIELD_EDIT '), 'control_groups': log.count('UI_CONTROL_PASS '), 'scope': 'Production SwiftUI and NSTextView in transparent nonactivating AppKit windows that cannot become key/main; actual key/main state checked around validation, controls, capture and field edits; fixture PID only; synthetic data; native selection/scroll checks use owned AppKit controls and Store updates; whole-panel AX inspections enumerate every pressable control and require exactly bottom-left copy and bottom-right voice capsule, no visible static state labels; native copy-host menu opens empty-panel settings; transcript-host AXShowMenu menus cover edit, latest, modes, bind/insert availability and navigation; render-only mode captures all three ordinary states and standby while background review remains active; voice entry and preference toggles do not change capture; capture actions and first-connection credentials/verification are injected; TEST_ONLY live-shaped receipt is controller evidence only; first-connection and compact-panel fixtures use no Keychain; preceding settings render performs scoped metadata presence only, no credential reads; only a unique private pasteboard is written for selected/full copy; no provider/network/microphone/global keys/general clipboard access/external target; candidate activation rejected; outside foreground transitions recorded without causal claims'}, ensure_ascii=False, indent=2) + '\n')
    print(log)
    raise SystemExit(0 if passed else 1)
