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
    for stage in json.loads((args.output/'receipt.json').read_text())['stages']:
        print(stage['stage'], stage['fontPt'],stage['controls'])


if __name__ == '__main__':
    main()
