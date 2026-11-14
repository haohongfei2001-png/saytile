from pathlib import Path
import json,runpy,difflib,re,collections
root=Path('/private/tmp/saytile-eos-experiment/440');work=Path('/private/tmp/saytile-preview-013');scorer=runpy.run_path(str(work/'scripts/score-local-asr.py'));norm=scorer['norm']
refs={x['id']:x for n in ('paired','aishell') for x in json.loads((work/'evidence/mandarin'/(n+'.json')).read_text())}
r=json.loads((root/'comparison.json').read_text());comparison=r['comparison']['476'];changes=[];counts=collections.Counter()
for x in comparison['differences']:
 before=x['before']['text'];after=x['after']['text'];a,b=norm(before),norm(after);edits=[];flags=set()
 for kind,i,j,k,l in difflib.SequenceMatcher(None,a,b,autojunk=False).get_opcodes():
  if kind=='equal':continue
  old,new=a[i:j],b[k:l];span=old+new
  if re.search(r'[0-9零〇一二两三四五六七八九十百千万亿]',span):flags.add('number_char_change_needs_context_review')
  if re.search(r'[不没无未非否勿]',span):flags.add('negation_char_change_needs_context_review')
  if re.search(r'[a-zA-Z]',span):flags.add('latin_spelling_change')
  edits.append(dict(kind=kind,before=old,after=new,old_range=[i,j],new_range=[k,l],before_context=a[max(0,i-8):min(len(a),j+8)],after_context=b[max(0,k-8):min(len(b),l+8)]))
 delta=x['after_score']['errors']-x['before_score']['errors'];counts['worse' if delta>0 else 'better' if delta<0 else 'equal_cer']+=1;counts['error_delta']+=delta
 changes.append(dict(id=x['id'],reference=refs[x['id']]['reference'],before=before,after=after,before_score=x['before_score'],after_score=x['after_score'],error_delta=delta,lexical_edits=edits,review_flags=sorted(flags),states_before=x['before']['states'],states_after=x['after']['states']))
aggregate={name:{'before_errors':c['before']['errors'],'after_errors':c['after']['errors'],'reference_units':c['after']['reference_units'],'delta':c['after']['errors']-c['before']['errors'],'before_cer':c['before']['errors']/c['before']['reference_units'],'after_cer':c['after']['errors']/c['after']['reference_units']} for name,c in comparison['cohorts'].items()}
report=dict(experimental=True,dirty=True,decision='PENDING_ROOT_QUALITY_REVIEW',initial_per_clip_screen=r['accuracy_gate'],screen_scope='This was an initial conservative experiment screen, not a user-mandated adoption condition. All regressions retained; net accuracy and critical content require review.',aggregate=aggregate,changed_clip_counts=dict(counts),flags_scope='Character/span flags only identify review candidates. They are NOT entity accuracy scores or confirmed semantic errors; CJK names need contextual review.',coverage=r['verified_eos_path_coverage'],changes=changes)
(root/'quality-review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:report[k] for k in ('decision','aggregate','changed_clip_counts')},ensure_ascii=False,indent=2))
