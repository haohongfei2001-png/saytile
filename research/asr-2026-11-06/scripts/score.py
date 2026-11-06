#!/usr/bin/env python3
"""Provider-neutral scoring; never rewrites source hypotheses or fills failed calls."""
import argparse, collections, json, math, re, unicodedata
from pathlib import Path

def normalize(text):
    # Freeze before running: NFKC + case fold + punctuation spacing. NO number,
    # traditional/simplified, synonym, filler, negation, or spelling substitutions.
    text=unicodedata.normalize('NFKC',text).casefold()
    kept=[]
    for i,c in enumerate(text):
        before=text[i-1] if i else ''
        after=text[i+1] if i+1<len(text) else ''
        numeric=(c in '+-−' and after.isdigit()) or (c in '.,:/' and before.isdigit() and after.isdigit()) or (c in '%°' and before.isdigit())
        kept.append(c if numeric or unicodedata.category(c)[0] not in 'PS' else ' ')
    text=''.join(kept)
    return ' '.join(text.split())

def tokenize(text,kind):
    s=normalize(text)
    if kind=='cer':return [c for c in s if not c.isspace()]
    if kind=='wer':return s.split()
    return re.findall(r'[-+−]?\d+(?:[.,:/]\d+)*(?:[%°])?|[\u3400-\u4dbf\u4e00-\u9fff]|[a-z0-9]+(?:[’\x27][a-z0-9]+)*|[^\W\s]',s,re.UNICODE)

def align(ref,hyp):
    # Deterministic Levenshtein alignment. Tie order: equal/substitute, delete, insert.
    # Insertion rate is an alignment proxy, NOT a semantic hallucination verdict.
    prev=[(i,0,0,i) for i in range(len(hyp)+1)]
    for i,a in enumerate(ref,1):
        cur=[(i,0,i,0)]
        for j,b in enumerate(hyp,1):
            p=prev[j-1];diag=(p[0]+(a!=b),p[1]+(a!=b),p[2],p[3])
            p=prev[j];dele=(p[0]+1,p[1],p[2]+1,p[3]);p=cur[j-1];ins=(p[0]+1,p[1],p[2],p[3]+1)
            cur.append(min([diag,dele,ins],key=lambda x:x[0]))
        prev=cur
    e,s,d,i=prev[-1];return {'errors':e,'substitutions':s,'deletions':d,'insertions':i,'reference_units':len(ref),'hypothesis_units':len(hyp),'error_rate':e/len(ref) if ref else None}

def percentile(x,q):
    if not x:return None
    x=sorted(x);return x[min(len(x)-1,max(0,math.ceil(q*len(x))-1))]

def score(manifest,records):
    lookup={x['id']:x for x in records};rows=[]
    for item in manifest:
        r=lookup.get(item['id']);lang=item['language'];kind={'zh':'cer','en':'wer','mixed':'mer'}.get(lang,'mer')
        if r is None:
            rows.append({'id':item['id'],'status':'NOT_RUN','group':item['group'],'language':lang});continue
        hyp=r.get('text','');ref=item['reference'];status='FAILED' if r.get('error') else 'OK'
        metrics=align(tokenize(ref,kind),tokenize(hyp,kind));raw=align(list(ref),list(hyp))
        # All manifest annotations precede inference. Exact lexical recall is a
        # strict diagnostic, NOT an assertion of semantic equivalence/opposition.
        entities=[]
        for ent in item.get('critical',[]):
            aliases=ent.get('accepted_forms',[ent['text']]);found=any(normalize(v).replace(' ','') in normalize(hyp).replace(' ','') for v in aliases)
            entities.append({**ent,'matched':found})
        rows.append({'id':item['id'],'status':status,'group':item['group'],'language':lang,'metric':kind,**metrics,'raw_characters':raw,'reference':ref,'hypothesis':hyp,'normalized_reference':normalize(ref),'normalized_hypothesis':normalize(hyp),'critical':entities,'first_readable_seconds':r.get('first_readable_seconds'),'stable_after_input_seconds':r.get('stable_after_input_seconds'),'elapsed_seconds':r.get('elapsed_seconds'),'error':r.get('error')})
    groups={}
    for group,lang in sorted({(x['group'],x['language']) for x in rows}):
        data=[x for x in rows if x['group']==group and x['language']==lang];ran=[x for x in data if x['status']!='NOT_RUN'];scorable=[x for x in ran if x.get('reference_units',0)>0];n=sum(x['reference_units'] for x in scorable)
        entities=[e for x in ran for e in x.get('critical',[])];times=[x['first_readable_seconds'] for x in ran if x.get('first_readable_seconds') is not None];ends=[x['stable_after_input_seconds'] for x in ran if x.get('stable_after_input_seconds') is not None]
        sums={k:sum(x.get(k,0) for x in scorable) for k in ['errors','substitutions','deletions','insertions']}
        groups[group+'/'+lang]={'expected':len(data),'run':len(ran),'not_run':len(data)-len(ran),'failures':sum(x['status']=='FAILED' for x in ran),'empty_on_speech':sum(not x.get('hypothesis','').strip() for x in scorable),'reference_units':n,**sums,'micro_error_rate':sums['errors']/n if n else None,'deletion_rate':sums['deletions']/n if n else None,'insertion_rate_proxy':sums['insertions']/n if n else None,'critical_annotated':len(entities),'critical_missed_exact':sum(not e['matched'] for e in entities),'first_readable_p50':percentile(times,.5),'first_readable_p95':percentile(times,.95),'stable_after_input_p50':percentile(ends,.5),'stable_after_input_p95':percentile(ends,.95)}
    return {'normalization':'v1_nfkc_casefold_punctuation_space_no_lexical_rewrite','groups':groups,'rows':rows}

def main():
    p=argparse.ArgumentParser();p.add_argument('--manifest',required=True);p.add_argument('--results',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    m=json.loads(Path(a.manifest).read_text());r=[json.loads(l) for l in Path(a.results).read_text().splitlines() if l.strip()]
    ids=[x['id'] for x in r]
    if len(ids)!=len(set(ids)):raise ValueError('duplicate experiment IDs; do not overwrite/retry invisibly')
    result=score(m,r);Path(a.output).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result['groups'],ensure_ascii=False,indent=2))
if __name__=='__main__':main()
