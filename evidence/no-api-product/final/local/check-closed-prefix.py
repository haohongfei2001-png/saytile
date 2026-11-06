#!/usr/bin/env python3
"""One read-only early diagnostic of closed synthetic recordings; never a full-run verdict."""
import json,pathlib,re,sqlite3,time,wave
out=pathlib.Path(__file__).resolve().parent
matches=re.findall(r'^Data directory: (/.+)$',(out/'realtime-run.log').read_text(),re.M)
root=pathlib.Path(matches[-1]);assert str(root).startswith('/tmp/saytile-rc-realtime-data.')
reference=json.loads((out/'conversion-reference.json').read_text())
with sqlite3.connect('file:'+str(root/'Saytile.sqlite')+'?mode=ro',uri=True) as db:
 rows=db.execute('select c.path,c.frames from chunks c join recordings r on r.id=c.recording_id where r.is_recording=0 order by r.created_at,c.ordinal').fetchall()
frames=0
with pathlib.Path(reference['reference_path']).open('rb') as r:
 for path,n in rows:
  with wave.open(str(root/'Audio'/path),'rb') as w:
   payload=w.readframes(n);assert len(payload)==n*2
   assert payload==r.read(len(payload)), 'Closed recording prefix differs from full conversion reference'
  frames+=n
result={'status':'PREFIX_PASS','scope':'Only already-closed synthetic recording prefix; complete30min still pending','unix':time.time(),'chunks':len(rows),'frames':frames,'seconds':frames/16000,'all_compared_sample_bytes_equal':True}
(out/'realtime-closed-prefix.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
