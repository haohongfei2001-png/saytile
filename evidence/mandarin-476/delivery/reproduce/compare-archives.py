from pathlib import Path
import json,sys,hashlib,collections,runpy
base,new,out=map(Path,sys.argv[1:4]);rating=runpy.run_path('scripts/score-local-asr.py')['rating']
grouped={}; diffs=[]
for name in ('paired','aishell'):
 file=name+'-qwen-small-product.jsonl'
 arrays=[[json.loads(x) for x in (d/'runs'/file).read_text().splitlines()] for d in [base,new]]
 refs=json.loads((Path('evidence/mandarin')/(name+'.json')).read_text())
 for r,b,c in zip(refs,*arrays,strict=True):
  assert r['id']==c['id']==b['id'] and c['providers']==b['providers']==['qwen-small']
  cohort='derived-20' if r['source'] in ['quiet','noise15db'] else 'public-420'
  s=grouped.setdefault(cohort,dict(before=collections.Counter(),after=collections.Counter(),exact_text=0,exact_states=0))
  for label,x in [('before',b),('after',c)]:
   s[label].update(rating(r['reference'],x['text']))
   s[label].update(rows=1,incomplete_subsegments=x['states'].count('failed'),empty_archives=int(not x['text']))
  s['exact_text']+=c['text']==b['text'];s['exact_states']+=c['states']==b['states']
  if c['text']!=b['text'] or c['states']!=b['states']:diffs.append({'id':r['id'],'before':b,'after':c})
result=dict(baseline=json.loads((base/'bench-identity.json').read_text())['source'],candidate=json.loads((new/'bench-identity.json').read_text())['source'],cohorts=grouped,differences=diffs)
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(result['cohorts'])
