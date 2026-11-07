from pathlib import Path
import tempfile,subprocess,datetime,json
out=Path('evidence/no-api9.1/sustained');i=json.loads((out/'soak/interval.json').read_text());end=int(datetime.datetime.fromisoformat(i['due_utc']).timestamp())
with tempfile.TemporaryDirectory(prefix='saytile-91-power-') as t:
 exe=Path(t)/'observe';subprocess.run(['clang','-Wall','-Wextra','-Werror','-O2',out/'ResourceObserver.c','-o',exe],check=True)
 with (out/'process-resource.jsonl').open('x') as f:subprocess.run([exe,str(i['pid']),str(end)],stdout=f,check=True)
