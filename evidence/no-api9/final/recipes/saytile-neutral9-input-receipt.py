import hashlib,json,struct,zlib
from pathlib import Path
from collections import Counter
p=Path('evidence/no-api9/final')
load=lambda f:json.loads((p/f).read_text())
def dump(f,obj): (p/f).write_text(json.dumps(obj,indent=2,sort_keys=True,ensure_ascii=False)+'\n')
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
src=load('input/native-source.before.json');aft=load('input/native-source.after.json');pkg=load('package-identity.json')
assert all(src[k]==aft[k] for k in ('head','tree','dirty_tracked_inputs','input_digest','files'))
assert src['head']==pkg['source_revision'] and src['tree']==pkg['tree'] and not src['dirty_tracked_inputs']
assert sha(Path(pkg['app_path'])/'Contents/MacOS/Saytile')==pkg['binary_sha256']
assert sha(Path(pkg['dmg_path']))==pkg['dmg_sha256']
n=load('input/native-binary-identities.json');o=load('owned-range/binary-identities.json');q=load('owned-range/summary.json')
assert len(n)==4 and len(o)==3 and all(i['unchanged'] and i['sha256_before']==i['sha256_after'] for i in n+o)
assert q['status']=='PASS' and len(q['scenarios_passed'])==9 and not q['source_changed_during_run']
source={'source_revision':src['head'],'source_tree':src['tree'],'tracked_input_digest':src['input_digest'],'tracked_input_count':len(src['files']),'tracked_inputs_unchanged':True}
nat=(p/'input/input-native-coordinator.log').read_text()
wk=(p/'input/input-webkit-observer.log').read_text()
assert all(item in nat for item in ('RC_AX_COORDINATOR_PASS 9 checks', 'TARGET_MUTATION_PASS 5 checks; production_dispatches=1 external_mutations=1 no_replay=true', 'PASS real native fixture never sends','PASS uncertain insertion ledger is durable with no owned range'))
assert all(item in wk for item in ('WEB_INSERT_RESULT unverified','WEB_ACTUAL_TEXT unchanged_fixture=true expected_inserted=false','WEB_AX_PROBE_COMPLETE observerChecks=6/6','PASS automatic binding rejects largeTree','PASS automatic binding rejects blankContext','PASS real WKWebView fixture never sends'))
dump('input/native-receipt.json',dict(source,ordinary_native_checks=9,target_mutation_checks=5,production_dispatches_in_mutation_case=1,independent_target_mutations=1,uncertain_replay=False,wk_context_checks=6,wk_capability_refusals=2,wk_dispatch='unverified',send_events=0,owned_range_scenarios=len(q['scenarios_passed']),native_binaries_unchanged=len(n),owned_range_binaries_unchanged=len(o),foreground_resolver='NOT_RUN',fixture_scope='Own synthetic native/WK fields and selection seam. No personal foreground draft, global key, real microphone or cloud.'))

for name in ('input/NATIVE-INPUT.md','owned-range/README.md'):
 old=(Path('evidence/no-api8/final')/name).read_text().replace('69b90939fd688b35448f976950e96db0ce5b602a',src['head']).replace('06f1ac6982591bce64c98bd93e26eb0ccba0cfd8',src['tree']).replace('38aa766fc26cdff368ee0c821e8e966a007f96941639fb4fac33dbbf88a4',src['input_digest'])
 (p/name).write_text(old)
print(src['head'],source['tracked_input_count'],q['status'],len(q['scenarios_passed']))
