#!/usr/bin/env python3
"""Run real AppKit scroll wheel and trackpad-phase events only within a fixture window."""
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
    parser.add_argument('--expect-pass', action='store_true', help='Exit nonzero unless both wheel and precise paths pass')
    args = parser.parse_args()
    sha = subprocess.check_output(['git', 'rev-parse', '--verify', args.source + '^{commit}'], cwd=ROOT, text=True).strip()
    with tempfile.TemporaryDirectory(prefix='saytile-reader-') as folder:
        tmp = Path(folder)
        archive = subprocess.check_output(['git', 'archive', sha, 'Sources/SaytileVoiceUI'], cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            for member in tar.getmembers():
                if member.isfile() and member.name.endswith('.swift'):
                    (tmp / Path(member.name).name).write_bytes(tar.extractfile(member).read())
        executable = tmp / 'ReaderViewportProbe'
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-module-cache-path', str(Path(tempfile.gettempdir()) / 'saytile-reader-module-cache'),
                        *map(str,sorted(tmp.glob('*.swift'))), str(ROOT/'tests/fixtures/ReaderViewportProbe.swift'), '-o',str(executable)],check=True)
        args.output.parent.mkdir(exist_ok=True, parents=True)
        subprocess.run([str(executable), sha, str(args.output.resolve())],check=True)
    result = json.loads(args.output.read_text())
    # 1 pt tolerates rounding on both 1x and 2x displays. Offsets are measured
    # on identical glyphs, after removing travel originally requested by the user.
    passed = True
    for case in result['cases']:
        edges = case['pageChanges']
        up = sum(e['older'] for e in edges)
        down = len(edges) - up
        checks = {
            'traversesMultiplePagesBothWays': up >= 3 and down >= 3,
            'sameGlyphsAcrossEverySwap': bool(edges) and all(e['common'] > 0 for e in edges),
            'pageResidualWithin1pt': all(e['maxUnexpectedDY'] is not None and e['maxUnexpectedDY'] <= 1 for e in edges),
            'horizontalMedianWithin1pt': all(e['medianAbsDX'] is not None and e['medianAbsDX'] <= 1 for e in edges),
            'lateOffscreenRevisionsHoldReading': all(e['common'] > 0 and e['maxAbsDY'] <= 1 and e['medianAbsDX'] <= 1 for e in case['lateRevisions']),
            'neverTookKey': not case['everKey'],
            'precisePhasesAndMomentumObserved': case['input'] != 'precise' or (
                {1, 4, 8} <= {e['phase'] for e in case['steps']} and {1, 4, 8} <= {e['momentum'] for e in case['steps']}),
        }
        case['checks'] = checks
        passed &= all(checks.values())
        print(case['input'], up, 'older pages;', down, 'newer pages; maximum unexpected vertical shift',
              round(max((e['maxUnexpectedDY'] or 0 for e in edges), default=0), 2), 'pt;', checks)
    result['status'] = 'PASS' if passed else 'FAIL'
    args.output.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')
    return int(args.expect_pass and not passed)


if __name__ == '__main__':
    raise SystemExit(main())
