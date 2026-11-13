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
        executable = tmp / 'AdaptiveVoicePanelProbe'
        subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','6','-module-cache-path',str(Path(tempfile.gettempdir())/'saytile-reader-module-cache'),
                       *flags, *map(str,sorted(tmp.glob('*.swift'))),str(ROOT/'tests/fixtures/AdaptiveVoicePanelProbe.swift'),'-o',str(executable)],check=True)
        args.output.mkdir(exist_ok=True,parents=True)
        subprocess.run([str(executable),sha,str(args.output.resolve())],check=True)
    receipt = args.output / 'receipt.json'
    report = json.loads(receipt.read_text())
    checks = {}
    stages = {stage['stage']: stage for stage in report['stages']}
    for name, stage in stages.items():
        width, height = stage['contentPt'][2:]
        controls = stage['controls']
        compact = width <= 80
        # The captured windows are all Retina. Allow half a logical point of
        # origin/size rounding when reading AX bounding boxes from WindowServer.
        def size_of(key, expected):
            return len(controls.get(key, [])) == 1 and all(abs(v-w) <= 0.5 for v,w in zip(controls[key][0][2:],expected))
        checks[name + '/voice'] = size_of('panel.capture', [54,26])
        checks[name + '/font'] = abs((stage['fontPt'] or 0)-14.04) < 0.01
        if compact:
            checks[name + '/onlyVoice'] = set(controls) == {'panel.capture'}
            frame = controls.get('panel.capture', [[0,0,0,0]])[0]
            checks[name + '/centered'] = abs(frame[0] + frame[2]/2 - width/2) <= .5 and abs(frame[1] + frame[3]/2 - height/2) <= .5
        else:
            checks[name + '/editableSurface'] = stage['textExposedInAccessibilityTree'] and stage['editorHasAllText'] == True
            checks[name + '/copy'] = ('panel.copy' not in controls if name in ['narrow','edge81'] else size_of('panel.copy',[30,26]))
    for key in ['pausePressed','resumePressed','centerClickPaused','editPersisted','imeStarted','imeSurvivedResize','imeCommittedOnce',
                'lateCandidateAfterSelectionReleased','compactRejectedKeyFocus']:
        checks[key] = report[key]
    checks['originalEditorAtEveryStage'] = all(s['sameEditor'] for s in stages.values())
    checks['retainsSelectionWhileCollapsedAndRestored'] = all(stages[n]['selectionRetained'] for n in ['narrow','edge81','edge80','minimum','tallMinimum','restored'])
    checks['exactlyThreeIntentionalActions'] = report['toggleCount'] == 3
    checks['neverTookKey'] = not report['everTookKey']
    for name in ['left','right','top','bottom','voice']:
        hits = report['perimeterHits']
        checks[name + '/windowServer'] = hits.get(name) == 'panel' and hits.get(name+'BackdropControl') == 'backdrop'
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
