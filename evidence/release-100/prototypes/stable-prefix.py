import json,sys
from pathlib import Path
root=Path('/private/tmp/saytile-experience-023/evidence/experience-023')
files=list((root/'closure/paired16/qwen-current').glob('*/visible-raw.json'))+list((root/'final/variance').glob('*/[123]/qwen-preview/native/visible-raw.json'))
# Diagnostic only: production scoring remains unchanged. Exact current-candidate prefixes, no joins.
def common(texts):
 a=texts[0]
 for b in texts[1:]:
  n=0
  for x,y in zip(a,b):
   if x!=y:break
   n+=1
  a=a[:n]
 return a
for clauses in (True,False):
 rows=[]
 for f in files:
  data=json.loads(f.read_text());history=[];published='';first=None;fail=False;record=0
  for e in data.get('rawWorkerEvents',[]):
   if e['kind'] not in ('partial','final'):continue
   t=e['text'];frames=e['frames']
   if e['kind']=='final':
    rows.append({'file':str(f.relative_to(root)),'record':record,'prefix':published,'final':t,'conflict':bool(published and not t.startswith(published)),'first_t':first,'eos':e['t'],'interim_conflict':fail})
    history=[];published='';first=None;fail=False;record+=1;continue
   history.append((t,frames));history=history[-4:]
   if published and not t.startswith(published):fail=True;continue
   if len(history)<4 or frames-history[0][1]<16000:continue
   p=common([v[0] for v in history])[:-8]
   if clauses:
    # A completed acoustic clause must have observed following speech, not the decoder's trailing full stop.
    ends=[i+1 for i,c in enumerate(p) if c in '，。；！？,;!?']
    p=p[:ends[-1]] if ends else ''
   if len(p)>len(published) and p.startswith(published):
    published=p
    if first is None:first=e['t']
 print(json.dumps({'clauses':clauses,'segments':len(rows),'early':sum(bool(r['prefix']) for r in rows),'eos_conflicts':sum(r['conflict'] for r in rows),'interim_conflicts':sum(r['interim_conflict'] for r in rows)},ensure_ascii=False))
 Path('evidence/release-100/prototypes/stable-prefix-'+str(clauses)+'.json').write_text(json.dumps(rows,indent=2,ensure_ascii=False)+'\n')
