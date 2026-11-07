from pathlib import Path
import json,subprocess,sys,hashlib
src=Path(__file__).resolve().parents[4]
root=Path.cwd();same='0a0cdecab8eb099e1dc3bb21b4c15ba5c30c93f0'
assert not subprocess.check_output(['git','diff','--name-only',same,'HEAD','--','Sources','packaging','tests','scripts','Package.swift'],text=True)
for rel in ['evidence/no-api9.1','deliverables/no-api.9.1']:
    target=root/rel;target.mkdir(parents=True,exist_ok=True)
    args=['rsync','-a','--exclude=__pycache__','--exclude=.DS_Store','--exclude=*.sqlite*','--exclude=*.wav','--exclude=*.aiff','--exclude=/sustained/soak/samples.jsonl','--exclude=/sustained/soak/result.json','--exclude=/sustained/active/samples.jsonl','--exclude=/sustained/active/result.json','--exclude=/sustained/active/observations.json.gz','--exclude=/sustained/active-repeat/samples.jsonl','--exclude=/sustained/active-repeat/result.json','--exclude=/sustained/active-repeat/observations.json.gz','--exclude=/sustained/passive-wake.jsonl','--exclude=/sustained/process-resource.jsonl',str(src/rel)+'/',str(target)+'/']
    subprocess.run(args,check=True)
m=json.loads((root/'evidence/no-api9.1/app/identity.json').read_text())
assert hashlib.sha256((root/m['repo_dmg']).read_bytes()).hexdigest()==m['dmg_sha256']
