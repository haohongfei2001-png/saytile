"""Summarize every original run, including failed observations; never rerun or waive them."""
import collections,hashlib,json,runpy,tempfile
from pathlib import Path
R=Path(__file__).resolve().parents[2]
import argparse
p=argparse.ArgumentParser(description=__doc__)
for flag in ['root','manifest','audio']:p.add_argument('--'+flag,type=Path,required=True)
a=p.parse_args(); refs=json.loads(a.manifest.read_text())['samples']
score=runpy.run_path(str(R/'scripts/score-local-asr.py'))
cadence=runpy.run_path(str(R/'scripts/mandarin/score-live-cadence.py'))
reverse=runpy.run_path(str(R/'scripts/mandarin/score-preview-reversals.py'))['reversals']
report={'scope':'Original interleaved pair. Every arm retained. First-any measures actual visible reference words even after EOF; original before-EOS cadence remains separately reported.','routes':{},'final_pairs':[]}
allruns={}
for route in ['qwen-previous','qwen-current']:
 runs=[]; calls=[]; resources=[]
 with tempfile.TemporaryDirectory(prefix='saytile-release-score-') as t:
  flat=Path(t)
  for ref in refs:
   folder=a.root/'paired16'/route/ref['id'];d=json.loads((folder/'visible-raw.json').read_text());inv=json.loads((folder/'invocation.json').read_text());samples=json.loads((folder/'process-samples.json').read_text());runs.append(d);calls.append(inv)
   d=dict(d,audio_sha256=inv['audio_sha256'],exit_code=inv['exit_code'])
   (flat/f"qwen-small-{ref['id']}.json").write_text(json.dumps(d))
   resources.append({'cpu_s':max(s['app_cpu_s'] or 0 for s in samples)+max(s['workers_cpu_s'] for s in samples),'peak_footprint_MiB':max(sum(s['footprint'].values()) for s in samples)/2**20})
  measured=cadence['measure'](a.manifest,a.audio,flat,runs[0]['sha'],automatic=False)
  errors=collections.Counter(); first_any=[]; gap=[]
  for ref,d,row in zip(refs[:15],runs[:15],measured['rows'][:15]):
   errors.update(score['rating'](ref['reference'],''.join(reversed(d['archive']))))
   onset=row['onset'];pairs=cadence['bigrams'](ref['reference'])
   first=next((f['t']-onset for f in d['frames'] if f['t']>=onset and pairs.intersection(cadence['bigrams'](f['text']))),None)
   first_any.append({'id':ref['id'],'seconds':first,'before_input_end':first is not None and first+onset<row['end']})
   gap.extend(cadence['gaps'](cadence['layer_events'](d['frames'],pairs,onset,row['end'],False)[1]))
  report['routes'][route]={'source':runs[0]['sha'],'original_cadence':measured,'normal15':{
   'quality':score['pooled'](errors),'first_any_reference_word_s':score['quant']([x['seconds'] for x in first_any if x['seconds'] is not None]),'first_any_rows':first_any,'missing_first':sum(x['seconds'] is None for x in first_any),
   'missed_before_end':sum(not x['before_input_end'] for x in first_any),'visible_update_gap_s':score['quant'](gap),'eos_s':score['quant']([r['after_file_s'] for r in measured['rows'][:15]]),
   'aba':sum(len(reverse(d['publications'],d['endOfFile'])) for d in runs[:15]),'cpu_s':sum(r['cpu_s'] for r in resources[:15]),'peak_footprint_MiB':max(r['peak_footprint_MiB'] for r in resources[:15])},
   'failed_invocations':[c for c in calls if c['exit_code']!=0],
   'surface':{'archive_equal_count':sum(d['frames'][-1]['text']==''.join(reversed(d['archive'])) for d in runs),'observations':sum(len(d.get('surfaceStates',[])) for d in runs),'blockers':dict(collections.Counter(s['blocker'] for d in runs for s in d.get('surfaceStates',[]) if s.get('blocker')))},'resources':resources}
 allruns[route]=runs
report['final_pairs']=[{'id':ref['id'],'text_equal':b['archive']==c['archive'],'state_equal':b['recordStates']==c['recordStates']} for ref,b,c in zip(refs,allruns['qwen-previous'],allruns['qwen-current'])]
(a.root/'native-comparison-including-failure.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for k,v in report['routes'].items():print(k,json.dumps(v['normal15'],ensure_ascii=False))
