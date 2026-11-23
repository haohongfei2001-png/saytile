"""Report the same fixed reference/cadence scoring for Qwen closure builds."""
import argparse,collections,gzip,hashlib,json,runpy,shutil,tempfile
from pathlib import Path
R=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--root',type=Path,required=True);p.add_argument('--audio',type=Path,required=True)
p.add_argument('--manifest',type=Path,default=R/'evidence/experience-023/setup/panel16.json')
p.add_argument('--quality-input',type=Path,default=R/'evidence/release-021/quality/input440.json.gz')
p.add_argument('--quality-baseline',type=Path,default=R/'evidence/experience-023/final/product440-qwen-small.jsonl')
a=p.parse_args();manifest=a.manifest
refs=json.loads(manifest.read_text())['samples']
base=runpy.run_path(str(R/'scripts/score-local-asr.py'))
cadence=runpy.run_path(str(R/'scripts/mandarin/score-live-cadence.py'))
reverse=runpy.run_path(str(R/'scripts/mandarin/score-preview-reversals.py'))['reversals']
report={'scope':'Same 16 public PCM fixtures, serial AB/BA native runs, no microphone or artificial load; shared M5, not a quiescent machine. All failures retained.','routes':{}}
corpora={}
for label in ['qwen-previous','qwen-current']:
 with tempfile.TemporaryDirectory(prefix='saytile-closure-report-') as temp:
  flat=Path(temp);corpus=[];resources=[]
  for ref in refs:
   f=a.root/'paired16'/label/ref['id'];d=json.loads((f/'visible-raw.json').read_text());corpus.append(d)
   resources.append(json.loads((f/'process.json').read_text()))
   file=f/('qwen-small-'+ref['id']+'.json');shutil.copy(file,flat/file.name)
  sha=corpus[0]['sha'];assert all(d['sha']==sha for d in corpus)
  scored=cadence['measure'](manifest,a.audio,flat,sha,automatic=False)
  errors=collections.Counter()
  for ref,d in zip(refs[:15],corpus[:15]):errors.update(base['rating'](ref['reference'],''.join(reversed(d['archive']))))
  scored['normal15']={'quality':base['pooled'](errors),
   'first_display_s':base['quant']([r['display']['first_s'] for r in scored['rows'][:15]]),
   'first_worker_s':base['quant']([r['worker']['first_s'] for r in scored['rows'][:15]]),
   'timeline_update_gap_s':base['quant']([x for ref,d,row in zip(refs[:15],corpus[:15],scored['rows'][:15]) for x in cadence['gaps'](cadence['layer_events'](d['publications'],cadence['bigrams'](ref['reference']),row['onset'],row['end'],False)[1])]),
   'visible_update_gap_s':base['quant']([x for ref,d,row in zip(refs[:15],corpus[:15],scored['rows'][:15]) for x in cadence['gaps'](cadence['layer_events'](d['frames'],cadence['bigrams'](ref['reference']),row['onset'],row['end'],False)[1])]),
   'eos_s':base['quant']([r['after_file_s'] for r in scored['rows'][:15]]),
   'aba':sum(len(reverse(d['publications'],d['endOfFile'])) for d in corpus[:15]),
   'cpu_s':sum(d['combined_cpu_s'] for d in resources[:15]),
   'peak_footprint_MiB':max(d['peak_simultaneous_footprint_MiB'] for d in resources[:15])}
  scored['resources']=[{k:v for k,v in r.items() if k!='samples'} for r in resources]
  scored['surface']={'observations':sum(len(d.get('surfaceStates',[])) for d in corpus),
    'blockers':collections.Counter(s['blocker'] for d in corpus for s in d.get('surfaceStates',[]) if s.get('blocker')),
    'final_matches':sum(d['frames'][-1]['text']==''.join(reversed(d['archive'])) for d in corpus)}
  starts=[]
  for ref,d,row in zip(refs,corpus,scored['rows']):
   ready=next(e for e in d['rawWorkerEvents'] if e['kind']=='ready')
   raw=next(e for e in d['rawWorkerEvents'] if e['kind']=='partial' and e['text'])
   stages=ready.get('startup',[]); stage={s['stage']:s['uptime'] for s in stages}
   starts.append({'id':ref['id'],'ready_since_voice_s':ready['t']-row['onset'],
     'first_nonempty_after_ready_s':raw['t']-ready['t'],
     'tokenizer_wall_s':stage['Loading audio encoder weights...']-stage['Loading tokenizer...'] if stages else None,
     'worker_startup_wall_s':stage['ready']-stage['main'] if stages else None})
  scored['startup']=starts
  corpora[label]=corpus;report['routes'][label]=scored
report['paired_final_identical']=[{'id':r['id'],'text_equal':b['archive']==c['archive'],'state_equal':b['recordStates']==c['recordStates']} for r,b,c in zip(refs,corpora['qwen-previous'],corpora['qwen-current'])]
q=a.root/'quality/product440.jsonl'
if q.exists():
 inp=json.loads(gzip.decompress(a.quality_input.read_bytes()))
 old=[json.loads(l) for l in a.quality_baseline.read_text().splitlines()]
 new=[json.loads(l) for l in q.read_text().splitlines()];assert len(new)==len(inp)==440
 assert [r['id'] for r in old]==[r['id'] for r in new]==[r['id'] for r in inp]
 groups=collections.defaultdict(collections.Counter)
 for ref,d in zip(inp,new):
  assert ref['id']==d['id']; k='derived20' if ref['source'] in ['quiet','noise15db'] else 'original420';groups[k].update(base['rating'](ref['reference'],d['text']))
 report['quality440']={'groups':{k:base['pooled'](v) for k,v in groups.items()},'baseline_identical':sum(b['text']==c['text'] and b['states']==c['states'] for b,c in zip(old,new)), 'failed_rows':[d for d in new if 'failed' in d['states']]}
(a.root/'comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v['normal15'] for k,v in report['routes'].items()},ensure_ascii=False,indent=2))
print('identical finals',sum(r['text_equal'] and r['state_equal'] for r in report['paired_final_identical']))
