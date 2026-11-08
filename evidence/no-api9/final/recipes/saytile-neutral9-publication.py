"""Accept a terminal GitHub snapshot only for the bytes actually retrieved at the pinned publication commit."""
import sys,json,datetime,subprocess
from pathlib import Path
d=Path('evidence/no-api9/final')
rec=json.loads((d/'public-download.json').read_text())
pin=rec['publication_commit'];src=rec['source_revision']
runs=json.loads(sys.stdin.read())
assert len(runs)==2 and {r['name'] for r in runs}=={'Saytile native','Saytile design contracts'}
assert all(r['sha']==pin and r['status']=='completed' and r['conclusion']=='success' for r in runs)
prod=['Sources','tests','scripts','contracts','packaging','.github','Package.swift','Package.resolved']
delta=subprocess.check_output(['git','diff','--name-only',src,pin,'--',*prod],text=True).splitlines()
assert delta==[],delta
result={'publication_commit':pin,'source_revision':src,'product_and_existing_tests_diff':delta,'runs':runs,'scope':'GitHub automatically checked the public evidence and unchanged source. These are separate from the independently archived exact product SHA runs.','checked_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
(d/'protocol/publication-ci.json').write_text(json.dumps(result,indent=2)+'\n')
print('published candidate CI:', [(r['id'],r['conclusion']) for r in runs])
