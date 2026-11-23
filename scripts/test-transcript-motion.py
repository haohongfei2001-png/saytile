#!/usr/bin/env python3
"""Replay identical host updates into a revision's actual shared native panel."""
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
    parser.add_argument('--source', required=True, help='Git revision of SaytileVoiceUI')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--gif', type=Path, help='Optional separate unmeasured run rasterizing the burst scenario in AppKit')
    args = parser.parse_args()
    sha = subprocess.check_output(['git', 'rev-parse', '--verify', args.source + '^{commit}'], cwd=ROOT, text=True).strip()
    public = ROOT / 'evidence/internal-0.2/candidate-public-speech.jsonl'
    sample = next(row for row in map(json.loads, public.read_text().splitlines())
                  if row['id'] == 'fleurs-9eb2d543a0a36152-quiet')
    # Trim only the initial silence before the first recorded display event.
    # Every subsequent inter-event delta, correction and final string is preserved.
    frames = [item for item in sample['frames'] if item.get('text')]
    offset = frames[0]['t'] * 1000 - 100
    events = [{'ms': item['t'] * 1000 - offset, 'text': item['text'], 'final': False} for item in frames]
    events.append({'ms': sample['pipelineSettledAt'] * 1000 - offset, 'text': sample['archive'][0], 'final': True})
    scenarios = [{'name': sample['id'], 'events': events},
                 {'name': 'controlled-multiline-burst-and-revision', 'events': [
                     {'ms': 100, 'text': '今天', 'final': False},
                     {'ms': 480, 'text': '今天上午讨论过语音输入的连续性，希望在自然停顿后继续说话时，已经读过的文字仍然留在原来的位置。', 'final': False},
                     {'ms': 540, 'text': '今天上午讨论过语音输入的连续性，希望在自然停顿后继续说话时，已经读过的文字仍然留在原来的位置。尤其需要保证数字十五。', 'final': False},
                     {'ms': 700, 'text': '今天上午讨论过语音输入的连续性，希望在自然停顿后继续说话时，已经读过的文字仍然留在原来的位置。尤其需要保证数字五十。', 'final': False},
                     {'ms': 1200, 'text': '今天上午讨论过语音输入的连续性，希望在自然停顿后继续说话时，已经读过的文字仍然留在原来的位置。尤其需要保证数字五十。', 'final': True}]}]
    with tempfile.TemporaryDirectory(prefix='saytile-motion-') as folder:
        tmp = Path(folder)
        archive = subprocess.check_output(['git', 'archive', sha, 'Sources/SaytileVoiceUI'], cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            for member in tar.getmembers():
                if member.isfile() and member.name.endswith('.swift'):
                    (tmp / Path(member.name).name).write_bytes(tar.extractfile(member).read())
        files = sorted(tmp.glob('*.swift'))
        flags = ['-D', 'SAYTILE_HAS_LIVE_TAIL'] if 'var liveTailID:' in (tmp / 'PanelTimelineDocument.swift').read_text() else []
        executable = tmp / 'VoiceTranscriptMotionProbe'
        subprocess.run(['xcrun', 'swiftc', '-O', '-parse-as-library', '-swift-version', '6', '-module-cache-path', str(tmp / 'module-cache'),
                        *flags, *map(str, files), str(ROOT / 'tests/fixtures/VoiceTranscriptMotionProbe.swift'), '-o', str(executable)], check=True)
        fixture = tmp / 'scenarios.json'
        fixture.write_text(json.dumps(scenarios, ensure_ascii=False))
        args.output.parent.mkdir(exist_ok=True, parents=True)
        subprocess.run([str(executable), str(fixture), str(args.output.resolve()), sha], check=True)
        if args.gif:
            fixture.write_text(json.dumps(scenarios[-1:], ensure_ascii=False))
            args.gif.parent.mkdir(exist_ok=True, parents=True)
            subprocess.run([str(executable), str(fixture), str(tmp / 'capture-timing.json'), sha, str(args.gif.resolve())], check=True)
    result = json.loads(args.output.read_text())
    checks = ('finalExact', 'onlySubmittedPrefixes', 'selectionProtected', 'readingOriginHeld', 'copySnapshotHeld', 'editPersisted')
    for row in result['scenarios']:
        print(row['name'], row['displayedChanges'], 'changes;', round(row['largestScrollStepPoints'], 1), 'pt max;', {k: row[k] for k in checks})
    return int(any(not all(row[key] for key in checks) or row['everTookKey'] for row in result['scenarios']))


if __name__ == '__main__':
    raise SystemExit(main())
