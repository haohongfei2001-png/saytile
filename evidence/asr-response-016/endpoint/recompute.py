#!/usr/bin/env python3
"""Recompute only published endpoint evidence; never launch a recognizer."""
import argparse,json,pathlib,runpy
p=argparse.ArgumentParser();p.add_argument('--repo',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parent
rating=runpy.run_path(str(a.repo/'scripts/score-local-asr.py'))['rating']
def read(name):return json.loads((root/name).read_text())
def rows(name):return {r['id']:r for r in map(json.loads,(root/name).read_text().splitlines())}
refs={r['id']:r for r in read('full440-manifest.json')};old=rows('priority4-baseline75.jsonl')
for endpoint,name in [(50,'priority4-candidate50.jsonl'),(60,'finance-candidate60.jsonl')]:
  before=after=units=0
  for i,new in rows(name).items():
    b=rating(refs[i]['reference'],old[i]['text']);n=rating(refs[i]['reference'],new['text'])
    before+=b['errors'];after+=n['errors'];units+=n['reference_units']
    print(json.dumps({'id':i,'endpoint':endpoint,'baseline':b,'candidate':n,'same_text':old[i]['text']==new['text']},ensure_ascii=False))
  print(json.dumps({'endpoint':endpoint,'baseline_errors':before,'candidate_errors':after,'reference_units':units}))
