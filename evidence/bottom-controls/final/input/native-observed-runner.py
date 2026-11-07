#!/usr/bin/env python3
"""Run the unchanged default native fixture script, observing owned binary hashes only."""
from pathlib import Path
import datetime, hashlib, json, os, runpy, subprocess
ROOT=Path('/Users/hhf/.codex/worktrees/saytile-rc2-noapi6')
OUT=ROOT/'evidence/bottom-controls/final/input'
SCRATCH=Path(os.environ['SAYTILE_INPUT_SCRATCH']).resolve()
real_popen=subprocess.Popen
observed=[]
class ObservedPopen(real_popen):
    def __init__(self,args,*pos,**kw):
        path=Path(str(args[0])) if isinstance(args,(list,tuple)) and args else None
        if path is not None and path.is_file() and path.resolve().parent==SCRATCH:
            observed.append({'path':str(path.resolve()),'sha256_before':hashlib.sha256(path.read_bytes()).hexdigest(),'utc':datetime.datetime.now(datetime.timezone.utc).isoformat()})
        super().__init__(args,*pos,**kw)
subprocess.Popen=ObservedPopen
try:
    runpy.run_path(str(ROOT/'scripts/test-input-native.py'),run_name='__main__')
finally:
    for row in observed:
        p=Path(row['path']); row['sha256_after']=hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None
        row['unchanged']=row['sha256_before']==row['sha256_after']
    (OUT/'native-binary-identities.json').write_text(json.dumps(observed,indent=2)+'\n')
