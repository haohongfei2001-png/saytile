from pathlib import Path
import subprocess, tempfile, json, sys, datetime, hashlib
out=Path('evidence/no-api7/final')
source=json.loads((out/'package-identity.json').read_text())
pin=sys.argv[1]; assert len(pin)==40 and all(c in '0123456789abcdef' for c in pin)
name='deliverables/no-api.7/Saytile-1.0.0-rc.2-no-api.7-arm64.dmg'
url=f'https://raw.githubusercontent.com/haohongfei2001-png/saytile/{pin}/{name}'
with tempfile.TemporaryDirectory(prefix='saytile-public-noapi7-') as tmp:
 dest=Path(tmp)/'download.dmg'
 cmd=['curl','--proxy','http://127.0.0.1:7895','--proto','=https','--proto-redir','=https','--location','--max-redirs','2','--connect-timeout','12','--max-time','60','--silent','--show-error','--fail','--output',str(dest),url]
 subprocess.run(cmd,check=True)
 body=dest.read_bytes()
digest=hashlib.sha256(body).hexdigest(); assert digest==source['dmg_sha256'] and len(body)==source['dmg_bytes']
r={'source_revision':source['source_revision'],'publication_commit':pin,'url':url,'retrieved_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'bytes':len(body),'downloaded_sha256':digest,'matches_mounted_tested_dmg':True}
(out/'public-download.json').write_text(json.dumps(r,indent=2)+'\n')
print(digest,len(body),url)
