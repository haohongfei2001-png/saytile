"""Check the fixed two-clip / 45-second-silence diagnostic, preserving its harness failure.
The single-paragraph public_run assertion is not suitable for a natural paragraph gap.
This does not change that assertion, strip whitespace, or reclassify the original receipt.
"""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('directory',type=Path);p.add_argument('manifest',type=Path);a=p.parse_args()
d=json.loads((a.directory/'visible-raw.json').read_text());m=json.loads(a.manifest.read_text());i=json.loads((a.directory/'invocation.json').read_text());samples=json.loads((a.directory/'process-samples.json').read_text())
assert m['composition']['count']==2 and m['composition']['silence_seconds']==45
ready=[e for e in d['rawWorkerEvents'] if e['kind']=='ready'];final=[e for e in d['rawWorkerEvents'] if e['kind']=='final']
assert len(final)==2 and final[0]['text'] and final[0]['text']==final[1]['text']
# Exactly one paragraph break, justified by the known >15-second input gap.
# No normalization is permitted; raw archives and every final character must agree.
expected=final[0]['text']+'\n'+final[1]['text']
assert d['archive']==[final[1]['text'],final[0]['text']]
assert d['publications'][-1]['text']==d['frames'][-1]['text']==expected
assert d['recordStates']==['completed','completed'] and d['providers']==['qwen-small']
assert i['exit_code']==0 and i['source']==d['sha']
duration=(m['samples'][0]['duration']-45)/2
quiet=[s for s in samples if duration+37 < s['t'] < duration+43]
released=bool(quiet) and all('worker' not in s['footprint'] for s in quiet)
r={'source':d['sha'],'diagnostic_trace':True,'not_a_paired_latency_benchmark':True,
 'harness_status':'FAIL retained: original one-paragraph archive concatenation cannot represent the explicitly inserted 45-second gap',
 'independent_assertion':'Exact two final strings joined by one natural paragraph newline; both archive entries, timeline and laid-out native text verified',
 'ready_count':len(ready),'ready_events':ready,'finals':final,'released_during_quiet':released,'quiet_observations':quiet,
 'matching_repeat_final':True,'final_visible_matches_exact_two_paragraphs':True,'process_exit':i['exit_code']}
r['pass']=released and len(ready)==2
(a.directory/'summary.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');assert r['pass'],r
print(json.dumps({k:v for k,v in r.items() if k not in ['ready_events','finals','quiet_observations']},ensure_ascii=False,indent=2))
