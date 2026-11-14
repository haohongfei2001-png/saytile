#!/usr/bin/env python3
"""Exercise 478 -> 0.15 -> 478 -> 0.15 with generated data and additive schema-6 metadata only."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,plistlib,re,shutil,sqlite3,subprocess as sp,tempfile
ROOT=Path('/private/tmp/saytile-natural-paragraphs')
BASE='7fd9296d8eb2bd81379bbaa7287844d0d46703d5'
WORKER='9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e'
NAME='Saytile 中文识别候选.app'
PROBE=Path('/private/tmp/saytile-011-frozen-process/probe')
PROBE_SHA='bd2c057e228cd8f1f2285fe6526a0860a7398f114a6a7b0ee23b93e19fe68f68'
OLD_EXE='4b650a5d852a3f62658acd19d1854fa47b82f3a8ec53c8ef483fea997121e0a1'
def digest(p):
 with p.open('rb')as f:return hashlib.file_digest(f,'sha256').hexdigest()
def meta(app):return plistlib.loads((app/'Contents/Info.plist').read_bytes())
def sidecar(data,expected_count,expect_present):
 with sqlite3.connect((data/'Saytile.sqlite').as_uri()+'?mode=ro',uri=True)as db:
  schema=db.execute('PRAGMA user_version').fetchone()[0];assert schema==6
  assert db.execute('PRAGMA integrity_check').fetchone()==('ok',)
  assert not db.execute('PRAGMA foreign_key_check').fetchall()
  names={r[0]for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
  present={'timeline_paragraphs','natural_paragraph_schema'}.issubset(names)
  assert present==expect_present
  idle=db.execute('SELECT idle_seconds FROM timeline_settings WHERE singleton=1').fetchone()[0]
  if not present:return dict(present=False,idle_seconds=idle,schema=schema)
  rows=db.execute('SELECT position,paragraph_start,break_hidden FROM timeline_paragraphs ORDER BY position').fetchall()
  version=db.execute('SELECT singleton,version FROM natural_paragraph_schema ORDER BY singleton').fetchall()
  triggers=db.execute("SELECT name,sql FROM sqlite_master WHERE type='trigger' AND name='timeline_natural_paragraph'").fetchall()
  assert len(rows)==expected_count and version==[(1,2)] and len(triggers)==1
  positions={r[0]for r in db.execute('SELECT position FROM transcript_timeline')}
  assert {r[0]for r in rows}==positions and all(r[1]in positions and r[1]<=r[0]and r[2]in(0,1)for r in rows)
  assert not db.execute('SELECT 1 FROM transcript_timeline t LEFT JOIN timeline_paragraphs p ON t.position=p.position WHERE p.position IS NULL').fetchall()
  return dict(present=True,schema=schema,idle_seconds=idle,rows=rows,version=version,trigger_sha256=hashlib.sha256(json.dumps(triggers).encode()).hexdigest())
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('source');a=p.parse_args();assert re.fullmatch('[0-9a-f]{40}',a.source)
 driver=ROOT/'scripts/mandarin/check-app-rollback.py'
 frozen=sp.run(['git','-C',ROOT,'show',a.source+':scripts/mandarin/check-app-rollback.py'],check=True,capture_output=True).stdout
 assert driver.read_bytes()==frozen,'Shared migration primitives changed since selected source'
 spec=importlib.util.spec_from_file_location('source_bound_rollback',driver);common=importlib.util.module_from_spec(spec);spec.loader.exec_module(common)
 stage=Path('/private/tmp/saytile-natural-paragraphs-release-'+a.source[:8]);package=json.loads((stage/'package.json').read_text())
 assert package['source']==a.source and package['version']=='0.15' and package['worker_sha256']==WORKER
 old=stage/'baseline478'/NAME;new=stage/'installed'/NAME
 assert meta(old)['SaytileSourceRevision']==BASE and meta(old)['CFBundleVersion']=='478'
 assert meta(new)['SaytileSourceRevision']==a.source and meta(new)['CFBundleShortVersionString']=='0.15'
 assert all(meta(app)['CFBundleIdentifier']=='app.saytile.mac.mandarin-candidate' and meta(app)['SaytileSourceDirty'] is False for app in(old,new))
 assert int(meta(new)['CFBundleVersion'])>478
 assert digest(PROBE)==PROBE_SHA and not PROBE.is_symlink()
 assert all(digest(app/'Contents/Helpers/SaytileModelWorker')==WORKER for app in(old,new))
 assert digest(old/'Contents/MacOS/Saytile')==OLD_EXE and digest(new/'Contents/MacOS/Saytile')==package['app_executable_sha256']
 for app in(old,new):sp.run(['codesign','--verify','--deep','--strict',app],check=True)
 out=stage/'rollback.json';assert not out.exists(),'Do not replace prior evidence'
 identities=[common.binary_info(app)for app in(old,new)]
 with tempfile.TemporaryDirectory(prefix='saytile-015-rollback-')as folder:
  tmp=Path(folder).resolve();apps=[];profiles=[]
  for index,app in enumerate((old,new)):
   dest=tmp/str(index);dest.mkdir();apps.append(dest/app.name)
   common.run('cp','-cR',app,apps[-1]);assert common.binary_info(apps[-1])==identities[index]
   profiles.append(common.profile_contract(apps[-1],dest,identities[index]))
  assert profiles[0]==profiles[1]
  archive,upgrade,fresh,custom=(tmp/k for k in('original-fixture','test-copy','empty-candidate','custom-settings'))
  common.open_fixture(apps[0],archive,0);common.seed(archive,PROBE);common.open_fixture(apps[0],archive,2)
  initial=common.snapshot(archive,2);legacy_sidecar=sidecar(archive,2,False)
  shutil.copytree(archive,upgrade);shutil.copytree(archive,custom)
  common.open_fixture(apps[1],fresh,0);common.snapshot(fresh,0);fresh_state=sidecar(fresh,0,True)
  assert fresh_state['idle_seconds']==60
  steps=[];migrated=None
  for label,app in(('old',apps[0]),('candidate',apps[1]),('old_reopened',apps[0]),('candidate_reopened',apps[1])):
   common.open_fixture(app,upgrade,2);state=common.snapshot(upgrade,2);assert state==initial,label
   added=sidecar(upgrade,2,label!='old')
   if label=='candidate':
    expected=60 if legacy_sidecar['idle_seconds']==120 or legacy_sidecar['idle_seconds']<60 else legacy_sidecar['idle_seconds']
    assert added['idle_seconds']==expected;migrated=added
   elif label in('old_reopened','candidate_reopened'):assert added==migrated,label+' removed/changed paragraph metadata'
   steps.append(dict(step=label,records=2,logical_tables_sha256=state['table_sha256'],wav_sha256=sorted(state['wav_sha256'].values()),sidecar=added))
  # A rollback app leaves an intentionally hidden paragraph break intact.
  with sqlite3.connect(upgrade/'Saytile.sqlite')as db:db.execute('UPDATE timeline_paragraphs SET break_hidden=1 WHERE position=(SELECT min(position)FROM timeline_paragraphs)')
  hidden=sidecar(upgrade,2,True)
  for app in(apps[0],apps[1]):
   common.open_fixture(app,upgrade,2);assert common.snapshot(upgrade,2)==initial;assert sidecar(upgrade,2,True)==hidden
  # A custom >= 60-second setting is not reset by migration or rollback.
  with sqlite3.connect(custom/'Saytile.sqlite')as db:db.execute('UPDATE timeline_settings SET idle_seconds=180 WHERE singleton=1')
  for app in(apps[1],apps[0]):
   common.open_fixture(app,custom,2);assert common.snapshot(custom,2)==initial;assert sidecar(custom,2,True)['idle_seconds']==180
  assert common.snapshot(archive,2)==initial and sidecar(archive,2,False)==legacy_sidecar
 assert identities==[common.binary_info(app)for app in(old,new)]
 result=dict(status='PASS',identities=identities,app_storage_profiles=profiles,fixture=initial,steps=steps,natural_paragraph_sidecar='PASS',sidecar_schema_version=2,sqlite_schema_version=6,old_table_rows_unchanged=True,original_audio_hashes_unchanged=True,hidden_boundary_preserved_after_old_and_new_reopen=True,custom_180_second_setting_preserved=True,network='denied to every smoke and seed process',launch='temporary diagnostic directories only; no capture or inference',keychain='service-name contracts only; no secret read',empty_candidate_records=0,original_fixture_unchanged=True,installed_binaries_unchanged=True,runner_sha256=digest(Path(__file__)),shared_source_runner_sha256=hashlib.sha256(frozen).hexdigest())
 out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
