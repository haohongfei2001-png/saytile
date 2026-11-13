#!/usr/bin/env python3
"""Measure the actual native, nonactivating shared voice panel at a fixed series of sizes."""
import argparse
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--expect-pass', action='store_true')
    args = parser.parse_args()
    sha = subprocess.check_output(['git','rev-parse','--verify',args.source+'^{commit}'],cwd=ROOT,text=True).strip()
    with tempfile.TemporaryDirectory(prefix='saytile-adaptive-') as folder:
        tmp = Path(folder)
        data = subprocess.check_output(['git','archive',sha,'Sources/SaytileVoiceUI'],cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(data)) as tar:
            for member in tar.getmembers():
                if member.isfile() and member.name.endswith('.swift'):
                    (tmp / Path(member.name).name).write_bytes(tar.extractfile(member).read())
        flags = ['-D', 'SAYTILE_ADAPTIVE_SLOT'] if 'enum VoicePanelFootprint' in (tmp/'VoiceRailProportions.swift').read_text() else []
        # Exercise the window's event routing as well as the shared SwiftUI view.
        host_source = subprocess.check_output(['git', 'show', sha + ':Sources/SaytileApp/VoicePanel.swift'], cwd=ROOT)
        wrapper = tmp / 'PanelHost.swift'
        wrapper.write_bytes(subprocess.check_output(['git', 'show', sha + ':Sources/SaytileApp/ReferencePanelStyle.swift'], cwd=ROOT))
        full_card = b'compactCaptureAction' in host_source
        if full_card:
            flags += ['-D', 'SAYTILE_COMPACT_ACTION']
        package = tmp / 'kit'
        package.mkdir()
        (package / 'WindowPlacement.swift').write_bytes(subprocess.check_output(
            ['git', 'show', sha + ':Sources/SaytileKit/WindowPlacement.swift'], cwd=ROOT))
        cache = str(Path(tempfile.gettempdir()) / 'saytile-reader-module-cache')
        swift = ['xcrun', 'swiftc', '-swift-version', '6', '-module-cache-path', cache, '-parse-as-library']
        subprocess.run([*swift, '-emit-library', '-static', '-emit-module', '-module-name', 'SaytileKit',
                        '-emit-module-path', str(package / 'SaytileKit.swiftmodule'), str(package / 'WindowPlacement.swift'),
                        str(tmp / 'VoiceRailProportions.swift'), '-o', str(package / 'libSaytileKit.a')], check=True)
        shared = sorted(p for p in tmp.glob('*.swift') if p != wrapper)
        subprocess.run([*swift, '-emit-library', '-static', '-emit-module', '-enable-testing', '-module-name', 'SaytileVoiceUI',
                        '-emit-module-path', str(package / 'SaytileVoiceUI.swiftmodule'), *map(str, shared),
                        '-o', str(package / 'libSaytileVoiceUI.a')], check=True)
        (tmp / 'VoicePanel.swift').write_bytes(host_source)
        executable = tmp / 'AdaptiveVoicePanelProbe'
        subprocess.run([*swift, *flags, '-I', str(package), '-L', str(package), '-lSaytileKit', '-lSaytileVoiceUI', str(tmp/'VoicePanel.swift'), str(wrapper),
                       str(ROOT/'tests/fixtures/AdaptiveVoicePanelProbe.swift'),'-o',str(executable)],check=True)
        args.output.mkdir(exist_ok=True,parents=True)
        subprocess.run([str(executable),sha,str(args.output.resolve())],check=True)
        if b'struct VoicePanelLayout' in b''.join(p.read_bytes() for p in shared):
            gestures = tmp / 'VoiceRailGestureProbe'
            subprocess.run([*swift, '-I', str(package), '-L', str(package), '-lSaytileKit', '-lSaytileVoiceUI',
                            str(tmp / 'VoicePanel.swift'), str(ROOT / 'tests/fixtures/VoiceRailGestureProbe.swift'),
                            '-o', str(gestures)], check=True)
            with (args.output / 'gestures.log').open('w') as log:
                for phase in ('write', 'restore'):
                    subprocess.run([str(gestures), phase, str(tmp / 'placement.json')], stdout=log, check=True)

    receipt = args.output / 'receipt.json'
    report = json.loads(receipt.read_text())
    checks = {}
    stages = {stage['stage']: stage for stage in report['stages']}
    for name, stage in stages.items():
        width, height = stage['contentPt'][2:]
        controls = stage['controls']
        # AX rectangles are converted into points relative to the actual window.
        def size_of(key, expected):
            return len(controls.get(key, [])) == 1 and all(abs(v-w) <= 0.5 for v,w in zip(controls[key][0][2:],expected))
        checks[name + '/voice'] = size_of('panel.capture', [min(width,54),26])
        checks[name + '/font'] = abs((stage['fontPt'] or 0)-14.04) < 0.01
        if 'panel.capture' in controls:
            x, y, bw, bh = controls['panel.capture'][0]
            checks[name + '/bottomRight'] = (-0.5 <= width-x-bw <= 24 and -0.5 <= height-y-bh <= 24)
        if name in ('minimum','lowWide'):
            checks[name + '/hiddenText'] = not stage['textExposedInAccessibilityTree']
        if name in ('wide','default','smaller','narrow','tall72','control54','tall28','restored'):
            checks[name + '/editableSurface'] = stage['textExposedInAccessibilityTree'] and stage['editorHasAllText']
        if name in ('wide','default','restored'):
            checks[name + '/copy'] = size_of('panel.copy',[30,26])
        if width < 90:
            checks[name + '/copyHidden'] = 'panel.copy' not in controls
    for names in [('edge82','edge81','edge80','edge79'), ('control55','control54','control53')]:
        rects = [stages[n]['controls']['panel.capture'][0] for n in names if 'panel.capture' in stages[n]['controls']]
        checks[names[0] + '/continuousButton'] = len(rects) == len(names) and all(
            max(abs(a-b) for a,b in zip(current,previous)) <= 1.01 for current,previous in zip(rects[1:],rects))
    for sweep in report['resizeSweep']:
        label = sweep['axis'] + str(sweep['travel'])
        # A little mouse slop can delay the first 3 pt of a button drag. The
        # orthogonal dimension and pinned edges should not move at all.
        continuous = 'widthError' if sweep['axis'] == 'left' else 'heightError'
        orthogonal = 'heightError' if sweep['axis'] == 'left' else 'widthError'
        checks[label + '/trackedEveryPoint'] = sweep[continuous] <= 3.5 and sweep[orthogonal] <= 0.5
        checks[label + '/anchor'] = max(sweep['rightError'],sweep['bottomError']) <= 0.5
    for key in ['pausePressed','resumePressed','centerClickPaused','editPersisted','imeStarted','imeSurvivedMinimum','imeSurvivedResize','imeCommittedOnce',
                'lateCandidateAfterSelectionReleased','compactRejectedKeyFocus']:
        checks[key] = report[key]
    checks['originalEditorAtEveryStage'] = all(s['sameEditor'] for s in stages.values())
    checks['retainsSelectionWhileCollapsedAndRestored'] = all(stages[n]['selectionRetained'] for n in ['narrow','edge81','edge80','tall28','minimum','restored'])
    checks['exactlyThreeIntentionalActions'] = report['toggleCount'] == 3
    checks['neverTookKey'] = not report['everTookKey']
    for name in ['left','right','top','bottom','voice']:
        hits = report['perimeterHits']
        checks[name + '/windowServer'] = hits.get(name) == 'panel' and hits.get(name+'BackdropControl') == 'backdrop'
    for variant, samples in report['compactPixels'].items():
        checks['glass/' + variant] = all(samples[key] > 0.25 for key in ('left', 'right', 'top', 'bottom')) and samples['corner'] < 0.1
    for variant, matched in report['glyphs'].items():
        checks['glyph/' + variant] = matched
    for state in ('paused', 'standby', 'recognizing'):
        checks['border/' + state] = report['compactPixels'][state]['rim'] > report['compactPixels'][state + '-border-off']['rim'] + 0.05
    for key, passed in report['compactClicks'].items():
        checks['compactClick/' + key] = passed
    for button in ('panel.capture', 'panel.copy'):
        for corner in ('topLeft', 'topRight', 'bottomLeft', 'bottomRight'):
            key = button + '/' + corner
            checks[key] = report['buttonCorners'].get(key) is True
    report['checks'] = checks
    report['status'] = 'PASS' if all(checks.values()) else 'FAIL'
    receipt.write_text(json.dumps(report, ensure_ascii=False,indent=2)+'\n')
    print(report['status'], sum(checks.values()), '/', len(checks), 'checks. Failed:', [k for k,v in checks.items() if not v])
    return int(args.expect_pass and report['status'] != 'PASS')


if __name__ == '__main__':
    raise SystemExit(main())
