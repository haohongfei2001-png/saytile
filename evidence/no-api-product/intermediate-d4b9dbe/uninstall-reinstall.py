"""Disposable candidate removal/reinstall, real package and existing synthetic Store probe only."""
import hashlib,json,pathlib,plistlib,shutil,sqlite3,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[3]
source=root/'dist/Saytile.app'
probe=pathlib.Path('/tmp/saytile-final-d4b9dbe-static/probe')
assert hashlib.sha256(probe.read_bytes()).hexdigest()=='564b220bb9236eed3573143ca687ad4572cbff00618f37bac4b73822bf021427'
info=plistlib.loads((source/'Contents/Info.plist').read_bytes())
assert info['SaytileSourceRevision']=='d4b9dbe812b9084f1bf31c1817c7b67095e17fc7' and info['SaytileSourceDirty'] is False
logs=[]
def run(cmd):
 r=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=30)
 logs.append(r.stdout+r.stderr)
 assert r.returncode==0,(cmd[0],r.returncode)
def snapshot(data):
 with sqlite3.connect(data/'Saytile.sqlite') as db:
  tables=[r[0] for r in db.execute("select name from sqlite_master where type='table' and name not like 'sqlite_%' order by name")]
  return {'schema':db.execute('pragma user_version').fetchone()[0], 'tables':{t:sorted(db.execute('select * from "'+t+'"').fetchall(),key=repr) for t in tables},'audio':{str(p.relative_to(data)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (data/'Audio').rglob('*') if p.is_file()}}
with tempfile.TemporaryDirectory(prefix='saytile-uninstall-owned-') as temp:
 base=pathlib.Path(temp);app=base/'Applications/Saytile.app';data=base/'Data'
 run([probe,'seed-beta',data]);run(['ditto','--norsrc',source,app])
 run([app/'Contents/MacOS/Saytile','--data-directory',data,'--smoke-test'])
 before=snapshot(data)
 assert before['schema']==5 and len(before['tables']['recordings'])==1
 shutil.rmtree(app)
 assert not app.exists() and snapshot(data)==before
 run(['ditto','--norsrc',source,app]);run(['codesign','--verify','--strict',app])
 run([app/'Contents/MacOS/Saytile','--data-directory',data,'--smoke-test'])
 assert snapshot(data)==before
 result={'status':'PASS','checks':['remove_only_disposable_candidate_keeps_all_database_rows_and_original_audio','reinstall_identical_signed_candidate_opens_preserved_data'],'source_revision':info['SaytileSourceRevision'],'binary_sha256':hashlib.sha256((app/'Contents/MacOS/Saytile').read_bytes()).hexdigest(),'probe_sha256':hashlib.sha256(probe.read_bytes()).hexdigest(),'scope':'Owned temporary app/data only; no production directory, credential mutation, microphone, cloud call, or system security bypass'}
output=pathlib.Path(__file__).parent
(output/'uninstall-reinstall.json').write_text(json.dumps(result,indent=2)+'\n')
(output/'uninstall-reinstall.log').write_text('\n'.join(logs))
print(json.dumps(result,indent=2))
