"""Dirty-worker experiment only. Never marks its outputs as a shipping 476 run."""
from pathlib import Path
import argparse,hashlib,json,plistlib,subprocess as sp,time,runpy,collections,struct
p=argparse.ArgumentParser()
p.add_argument('--app',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
p.add_argument('--patch',type=Path,required=True,help='Exact uncommitted worker source diff used to build the experiment')
p.add_argument('--source-base',required=True,help='Source SHA before that worker diff')
a=p.parse_args();work=Path('/private/tmp/saytile-preview-013');old=Path('/private/tmp/saytile-local-quality-20261114');base=Path('/private/tmp/saytile-474-delivery/476')
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
info=plistlib.loads((a.app/'Contents/Info.plist').read_bytes());shipping=json.loads((base/'bench-identity.json').read_text())
assert info['SaytileSourceRevision']==shipping['source']=='0fbca1d892bbc8aa550c4439b8cfcb045af825ae'
assert info['CFBundleIdentifier']=='app.saytile.mac.mandarin-candidate'
assert info['CFBundleVersion']=='476' and info['CFBundleShortVersionString']=='0.13'
def signed_code_hash(path):
 # Ad-hoc re-signing changes LC_CODE_SIGNATURE and __LINKEDIT size fields.
 # Bind every other load-command byte and the entire pre-signature payload.
 data=path.read_bytes();header=list(struct.unpack_from('<IiiIIIII',data));assert header[0]==0xfeedfacf
 cursor=32;commands=[];signature=None
 for _ in range(header[4]):
  kind,length=struct.unpack_from('<II',data,cursor);assert length>=8
  command=bytearray(data[cursor:cursor+length])
  if kind==0x1d:signature=struct.unpack_from('<II',command,8)[0]
  else:
   if kind==0x19 and command[8:24].split(b'\0')[0]==b'__LINKEDIT':
    command[32:40]=b'\0'*8;command[48:56]=b'\0'*8
   commands.append(bytes(command))
  cursor+=length
 assert signature is not None and cursor==32+header[5] and signature>=cursor
 payload=data[cursor:signature];header[4]=len(commands);header[5]=sum(map(len,commands))
 return hashlib.sha256(struct.pack('<IiiIIIII',*header)+b''.join(commands)+payload).hexdigest()
host_sha=sha(a.app/'Contents/MacOS/Saytile')
original=Path(json.loads((base/'preflight.json').read_text())['app_path'])/'Contents/MacOS/Saytile'
assert sha(original)==shipping['sha256']['app'],'Shipping baseline executable changed'
host_code_sha=signed_code_hash(a.app/'Contents/MacOS/Saytile')
assert host_code_sha==signed_code_hash(original),'Experimental host code differs from shipping 476'
worker=sha(a.app/'Contents/Helpers/SaytileModelWorker');assert worker!=shipping['sha256']['worker'],'Experiment has no worker change'
assert a.patch.is_file() and a.patch.stat().st_size>0 and len(a.source_base)==40
sp.run(['codesign','--verify','--strict','--deep',a.app],check=True)
source=work/'.build/mandarin/bench/bin-shipping-0fbca1d8';cohort=json.loads((source/'identity.json').read_text());assert cohort['source']==shipping['source']
assert sha(source/'Cohort')==cohort['sha256']['cohort'],'Compiled Cohort bytes changed'
identity=dict(experimental=True,dirty=True,source='EXPERIMENTAL_DIRTY_WORKER',host_source=shipping['source'],worker_source_base=a.source_base,worker_patch_sha256=sha(a.patch),worker_sha256=worker,shipping_worker_sha256=shipping['sha256']['worker'],host_app_sha256=host_sha,shipping_host_app_sha256=shipping['sha256']['app'],host_macho_code_sha256_excluding_signature_and_linkedit_size=host_code_sha,host_code_exactly_shipping_476=True,cohort=cohort,app_path=str(a.app),provider='qwen-small',hypothesis='Full-PCM EOS recomputation with current-audio token verification; no preview promoted directly to final')
a.out.mkdir(parents=True,exist_ok=True);receipt=a.out/'bench-identity.json'
if receipt.exists():assert json.loads(receipt.read_text())==identity,'Cannot mix different experimental workers or source diffs'
receipt.write_text(json.dumps(identity,ensure_ascii=False,indent=2)+'\n');(a.out/'worker-source.patch').write_bytes(a.patch.read_bytes());runs=a.out/'runs';runs.mkdir(exist_ok=True)
rating=runpy.run_path(str(work/'scripts/score-local-asr.py'))['rating'];reference_by_id={};baselines={}
for version,folder in [('474',Path('/private/tmp/saytile-013-followup-bench/candidate')),('476',base)]:
 baselines[version]={r['id']:r for f in folder.glob('runs/*-product.jsonl') for r in map(json.loads,f.read_text().splitlines())}
assert all(len(v)==440 for v in baselines.values())
regressions=[]
for label in ('paired','aishell'):
 references=json.loads((work/'evidence/mandarin'/(label+'.json')).read_text());data=[];reference_by_id.update({r['id']:r for r in references})
 for path in sorted((old/'.build/mandarin/bench').glob(label+'-???.json')):
  assert not (a.out/'stop-after-shard').exists(),'Experiment stopped after completed shard'
  shard=json.loads(path.read_text());assert references[len(data):len(data)+len(shard)]==shard
  part=(runs/path.stem).with_suffix('.part');existing=part.read_text().splitlines() if part.exists() else []
  if existing:
   assert len(existing)==len(shard),'Incomplete shard is preserved, not overwritten/retried automatically'
   rows=list(map(json.loads,existing))
  else:
   with (runs/(path.stem+'.log')).open('w') as log:
    sp.run([source/'Cohort','qwen-small','product',path,old/'.build/mandarin/wav',old/'.build/local-asr/weights',a.app/'Contents/Helpers',part],cwd=a.app/'Contents/Resources',stdout=log,stderr=sp.STDOUT,check=True)
   rows=list(map(json.loads,part.read_text().splitlines()))
  assert [r['id'] for r in rows]==[r['id'] for r in shard]
  assert all(r['providers']==['qwen-small'] for r in rows),'Unexpected runtime provider'
  assert any(r['text'] for r in rows),'All-empty shard: stop for execution diagnosis'
  for ref,row in zip(shard,rows,strict=True):
   if not row['text'] or any(rating(ref['reference'],row['text'])['errors']>rating(ref['reference'],baselines[v][row['id']]['text'])['errors'] for v in baselines):
    regressions.append(row['id'])
  data.extend(rows);print(time.strftime('%X'),path.name,'complete; worse/empty clip IDs so far:',regressions,flush=True)
 assert len(data)==len(references)
 (runs/(label+'-qwen-small-product.jsonl')).write_text('\n'.join(json.dumps(r,ensure_ascii=False,sort_keys=True) for r in data)+'\n')
# Compare both full-text and same-normalizer CER, including per-clip worsening.
rows={r['id']:r for f in runs.glob('*-product.jsonl') for r in map(json.loads,f.read_text().splitlines())};assert len(rows)==440
results={}
for version,before in baselines.items():
 groups={};changes=[]
 for id,after in rows.items():
  ref=reference_by_id[id];prior=before[id];group='derived-20' if ref['source'] in ('quiet','noise15db') else 'public-420'
  stat=groups.setdefault(group,dict(before=collections.Counter(),after=collections.Counter(),exact_text=0,exact_states=0))
  for key,row in [('before',prior),('after',after)]:
   stat[key].update(rating(ref['reference'],row['text']));stat[key].update(rows=1,empty_archives=int(not row['text']),incomplete_subsegments=row['states'].count('failed'))
  stat['exact_text']+=after['text']==prior['text'];stat['exact_states']+=after['states']==prior['states']
  if after['text']!=prior['text'] or after['states']!=prior['states']:
   changes.append(dict(id=id,before=prior,after=after,before_score=rating(ref['reference'],prior['text']),after_score=rating(ref['reference'],after['text'])))
 results[version]=dict(cohorts=groups,differences=changes)
report=dict(experimental=True,dirty=True,identity=identity,comparison=results,per_clip_worse_or_empty=sorted(set(regressions)),accuracy_gate='REJECT' if regressions else 'PASS',timing_gate='NOT_RUN: full original-rate timing/EOS checks are separate and still required',verified_eos_path_coverage='NOT_OBSERVED: accelerated PCM may reach EOS before a preview draft exists; this corpus alone does not establish that token-verified EOS was exercised for every sample. Separate original-rate endpoint receipts are required.')
(a.out/'comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:report[k] for k in ('accuracy_gate','per_clip_worse_or_empty','timing_gate')},ensure_ascii=False),flush=True)
