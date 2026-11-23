import json,runpy,plistlib
from pathlib import Path
w=Path('/private/tmp/saytile-beta-021-20261123');root=Path('/private/tmp/saytile-021-563-smoke3');root.mkdir(exist_ok=True)
run=runpy.run_path(str(w/'scripts/mandarin/measure-preview-cost.py'))['public_run'];app=Path('/private/tmp/saytile-021-563-app/Saytile.app');manifest=w/'evidence/mandarin/panel-cohort.json';checks=[]
for name in ['fleurs-0ebe0fb634f8e4ac','fleurs-8e93e440f571a4da','ascend-mixed-ff9c42612780330b']:
 out=root/name
 if not (out/('auto-qwen-small-'+name+'.json')).exists(): run(app,manifest,name,w/'.build/local-asr/weights',w/'.build/mandarin/wav',out)
 f='auto-qwen-small-'+name+'.json';d=json.loads((out/f).read_text());previous=json.loads((Path('/private/tmp/saytile-021-561-fixed15')/f).read_text());assert d['archive']==previous['archive'];assert d['sha']=='8514fea5d45a778aae84854db9b139f7a1fbb85b'
 before=[v for v in d['publications'] if v['t']<d['endOfFile'] and v['text'].strip()];assert len({v['text'] for v in before})>=2
 checks.append({'sample':name,'final_text_equal_to_fixed15':True,'source':d['sha'],'archive_records':len(d['archive']),'publications':len(d['publications']),'displayed_changes':d['displayedChanges'],'pre_eof_distinct_texts':len({v['text'] for v in before}),'states':d['recordStates']})
(root/'receipt.json').write_text(json.dumps({'status':'PASS','scope':'final-package paced native smoke, not a new latency benchmark','checks':checks},indent=2)+'\n')
