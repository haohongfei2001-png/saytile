from pathlib import Path
import subprocess, json, hashlib, tempfile, datetime
out=Path.cwd()/'evidence/no-api9/final'; pack=json.loads((out/'package-identity.json').read_text())
app=Path(pack['app_path']); dmg=Path(pack['dmg_path'])
h=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
assert h(app/'Contents/MacOS/Saytile')==pack['binary_sha256'] and h(dmg)==pack['dmg_sha256']
def run(args):
 r=subprocess.run(args,capture_output=True,text=True,timeout=70)
 return {'command':[str(x) for x in args],'exit':r.returncode,'stdout':r.stdout.strip(),'stderr':r.stderr.strip()}
obs={
 'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_revision':pack['source_revision'],'binary_sha256':pack['binary_sha256'],'dmg_sha256':pack['dmg_sha256'],
 'system_assessment':run(['/usr/sbin/spctl','--status']),
 'code_integrity':run(['/usr/bin/codesign','--verify','--strict',app]),
 'executable_assessment':run(['/usr/sbin/spctl','--assess','--type','execute','-vv',app]),
 'scope':'Read-only Gatekeeper assessment of the exact extracted candidate. No launch via Finder, no quarantine edits, no policy change, no production install. A valid ad-hoc code signature is distinct from authorization to distribute on ordinary Macs.'}
assert obs['code_integrity']['exit']==0
(out/'gatekeeper.json').write_text(json.dumps(obs,ensure_ascii=False,indent=2)+'\n')
print(obs)
