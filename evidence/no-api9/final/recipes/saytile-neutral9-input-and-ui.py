from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,sys
parser=argparse.ArgumentParser()
parser.add_argument('phase',choices=['input','ui'])
parser.add_argument('sha')
parser.add_argument('tree')
args=parser.parse_args()
repo=Path('/Users/hhf/.codex/worktrees/saytile-rc2-neutral')
assert Path.cwd()==repo
sha=args.sha;tree=args.tree
def assert_source():
 assert subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()==sha
 assert subprocess.check_output(['git','rev-parse','HEAD^{tree}'],text=True).strip()==tree
 assert not subprocess.check_output(['git','diff','--name-only','HEAD','--','Sources','tests','scripts','packaging','Package.swift','Package.resolved'])
assert_source()
p=Path('evidence/no-api9/final')
inp=p/'input'
def hash_file(f): return hashlib.sha256(f.read_bytes()).hexdigest()
def logged(command,log,env=None):
 with log.open('x') as fd:
  r=subprocess.run(command,stdout=fd,stderr=subprocess.STDOUT,env=env)
 print(log,r.returncode,flush=True)
 return r.returncode
if args.phase=='input':
 inp.mkdir(parents=True,exist_ok=True);owned=p/'owned-range';owned.mkdir(exist_ok=True)
 for name in ['native-observed-runner.py','snapshot-source.py']:
  t=(Path('evidence/no-api7/final/input')/name).read_text().replace('/Users/hhf/.codex/worktrees/saytile-noapi6-evidence',str(repo)).replace('evidence/no-api7/final/input','evidence/no-api9/final/input')
  (inp/name).write_text(t)
 subprocess.run([sys.executable,inp/'snapshot-source.py',inp/'native-source.before.json'],check=True)
 scratch=Path('/tmp')/('saytile-final-noapi9-'+sha[:12]+'-input-team');assert not scratch.exists()
 env=dict(os.environ,SAYTILE_INPUT_SCRATCH=str(scratch),SAYTILE_INPUT_EVIDENCE_DIRECTORY=str(inp.resolve()))
 rc=logged([sys.executable,inp/'native-observed-runner.py'],inp/'native-run.log',env)
 if rc:sys.exit(rc)
 rc=logged([sys.executable,'scripts/test-owned-range-native.py'],owned/'run.log')
 lines=(owned/'run.log').read_text().splitlines();scratch=Path(next(x[8:] for x in lines if x.startswith('SCRATCH ')))
 for name in ['summary.json','probe.log','preflight.log']:
  if (scratch/name).exists():shutil.copyfile(scratch/name,owned/name)
 s=json.loads((scratch/'summary.json').read_text())
 ids=[]
 for name,before in s.get('binary_sha256',{}).items():
  f=scratch/name;after=hash_file(f)
  ids.append(dict(path=str(f),sha256_before=before,sha256_after=after,unchanged=before==after))
 (owned/'binary-identities.json').write_text(json.dumps(ids,indent=2)+'\n')
 print('owned',s['status'],len(s['scenarios_passed']),len(ids),flush=True)
 if rc:sys.exit(rc)
 assert s['head']==sha and not s['source_changed_during_run'] and len(ids)==3 and all(x['unchanged'] for x in ids)
 subprocess.run([sys.executable,inp/'snapshot-source.py',inp/'native-source.after.json'],check=True)
else:
 meta=json.loads((p/'package-identity.json').read_text())
 assert meta['source_revision']==sha and meta['tree']==tree and not meta['source_dirty']
 app=Path(meta['app_path']);assert hash_file(app/'Contents/MacOS/Saytile')==meta['binary_sha256']
 assert hash_file(Path(meta['dmg_path']))==meta['dmg_sha256']
 for d,extra in [('ui',['--controls']),('ui-render-only',[])]:
  out=p/d;assert not out.exists()
  rc=logged([sys.executable,'scripts/test-native-ui.py','--app',str(app),'--output',str(out),*extra],p/f'{d}-console.log')
  if rc:sys.exit(rc)
  m=json.loads((out/'manifest.json').read_text())
  assert m['passed'] and m['source_revision']==sha and not m['source_dirty'] and m['binary_sha256']==meta['binary_sha256']
  print(d,len(m['images']),len([n for n in m['images'] if n.startswith('reference-')]),m.get('reference_geometry_checks','see reference_geometry'),m['native_ax_press'],m['native_menu_select'],m['bottom_control_checks'],m['native_field_edits'],m['control_groups'],m['outside_foreground_observations'],flush=True)
 assert hash_file(app/'Contents/MacOS/Saytile')==meta['binary_sha256']
assert_source()
