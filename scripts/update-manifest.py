#!/usr/bin/env python3
"""Refresh the committed source/evidence integrity snapshot after staging new files."""
from pathlib import Path
import hashlib
import subprocess
root = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
lines = []
for name in sorted(paths):
    path = root / name
    if name and name != 'SHA256SUMS.txt' and path.is_file():
        lines.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {name}\n')
(root / 'SHA256SUMS.txt').write_text(''.join(lines))
