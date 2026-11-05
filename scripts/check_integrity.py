#!/usr/bin/env python3
from pathlib import Path
import hashlib,sys
root=Path(__file__).resolve().parents[1]
failed=[];count=0
for line in (root/'SHA256SUMS.txt').read_text().splitlines():
 expected,rel=line.split('  ',1);path=(root/rel).resolve()
 if not path.is_relative_to(root) or not path.is_file():failed.append(rel);continue
 actual=hashlib.sha256(path.read_bytes()).hexdigest();count+=1
 if actual!=expected:failed.append(rel)
print(f'Integrity: {count-len(failed)}/{count} matching files')
if failed:print('Mismatch:',', '.join(failed))
sys.exit(bool(failed))
