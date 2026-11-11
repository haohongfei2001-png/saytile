#!/usr/bin/env python3
"""Real child-process termination and actual beta-source upgrade, isolated under /tmp."""
import argparse, hashlib, json, os, pathlib, shutil, signal, sqlite3, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=pathlib.Path, default=ROOT/'research/asr/validation/rc2/storage-processes.json')
args = parser.parse_args()
SCRATCH = pathlib.Path(os.environ.get('SAYTILE_STORAGE_SCRATCH', '/tmp/saytile-rc2-storage'))
SCRATCH.mkdir(exist_ok=True)
args.output.parent.mkdir(parents=True, exist_ok=True)
base = ['swiftc','-O','-swift-version','6','-parse-as-library','-I','Sources/CSQLite']
fixture = 'tests/fixtures/StoreProcessProbe.swift'
build = ['swift','build','--product','SaytileKit','--scratch-path',str(SCRATCH/'build'),'-Xswiftc','-enable-testing']
subprocess.run(build,cwd=ROOT,check=True)
bin_dir = pathlib.Path(subprocess.check_output(build+['--show-bin-path'],cwd=ROOT,text=True).strip())
module_map = bin_dir/'../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap'
if not module_map.exists(): module_map = bin_dir/'CAudio.build/module.modulemap'
assert module_map.exists()
subprocess.run(base+['-D','SAYTILE_PACKAGE_PROBE','-I',str(bin_dir),'-I',str(bin_dir/'Modules'),
    '-Xcc','-fmodule-map-file='+str(module_map),'-L',str(bin_dir),'-lSaytileKit','-lc++',fixture,'-o',str(SCRATCH/'probe')],cwd=ROOT,check=True)
for label, revision, names in [
    ('beta','v1.0.0-beta.1',('Models','Store','StoreSQLite')),
    ('rc1','v1.0.0-rc.1',('Models','Store','StoreSQLite','StoreLock')),
]:
    source = SCRATCH/label; source.mkdir(exist_ok=True)
    for name in names:
        (source/(name+'.swift')).write_bytes(subprocess.check_output(['git','show',f'{revision}:Sources/SaytileKit/{name}.swift'],cwd=ROOT))
    subprocess.run(base+[str(source/(n+'.swift')) for n in names]+[fixture,'-o',str(SCRATCH/(label+'-probe'))],cwd=ROOT,check=True)
checks=[]
def run(binary,mode,directory,good=True):
    p=subprocess.run([str(SCRATCH/binary),mode,str(directory)],text=True,capture_output=True)
    if (p.returncode == 0) != good: raise RuntimeError(f'{mode}: {p.returncode}\n{p.stdout}\n{p.stderr}')
    print(p.stdout,end=''); return p

def snapshot(directory):
    with sqlite3.connect(directory/'Saytile.sqlite') as db:
        tables = [row[0] for row in db.execute("select name from sqlite_master where type='table' order by name")]
        data = {name: db.execute('select * from "'+name+'" order by rowid').fetchall() for name in tables}
        columns = {name: [row[1] for row in db.execute('pragma table_info("'+name+'")')] for name in tables}
        return {'schema': db.execute('pragma user_version').fetchone()[0], 'tables': data, 'columns': columns,
                'audio': {str(p.relative_to(directory)):hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sorted((directory/'Audio').rglob('*')) if p.is_file()}}

def killed(mode,directory,marker,check_lock=False):
    proc=subprocess.Popen([str(SCRATCH/'probe'),mode,str(directory)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        deadline=time.monotonic()+15
        while not (directory/marker).exists():
            if proc.poll() is not None: raise RuntimeError(proc.communicate())
            if time.monotonic()>deadline: raise TimeoutError(mode)
            time.sleep(.02)
        if check_lock:
            rejected=run('probe','open',directory,False)
            assert '另一个 Saytile' in rejected.stdout
            checks.append('second_process_rejected_without_mutating_live_store')
        os.kill(proc.pid,signal.SIGKILL);proc.wait(timeout=5)
        assert proc.returncode == -signal.SIGKILL
        checks.append(mode+'_sigkill')
    finally:
        if proc.poll() is None: proc.kill();proc.wait()
        proc.communicate()

with tempfile.TemporaryDirectory(prefix='process-fixtures-',dir=SCRATCH) as tmp:
    parent=pathlib.Path(tmp)
    run('probe','disk-fault',parent/'disk-fault');checks.append('real_kernel_write_failure_is_atomic_and_recoverable')
    for baseline in ['beta','rc1']:
        upgrade=parent/(baseline+'-upgrade')
        run(baseline+'-probe','seed-beta',upgrade)
        run(baseline+'-probe','open',upgrade)  # let the released store finish crash recovery
        before=snapshot(upgrade)
        backup=parent/(baseline+'-pre-upgrade-copy')
        shutil.copytree(upgrade,backup)  # stopped, disposable fixture only; no production backup is taken
        run('probe','verify',upgrade)
        after=snapshot(upgrade)
        assert before['schema']==(1 if baseline=='beta' else 2) and after['schema']==6
        # Schema 5 adds a recording upload-consent table. Compare every old
        # column/row exactly while allowing explicit schema additions.
        for name,rows in before['tables'].items():
            indices=[after['columns'][name].index(column) for column in before['columns'][name]]
            assert [tuple(row[index] for index in indices) for row in after['tables'][name]] == rows
        assert after['tables']['recording_cloud_authorizations'] == [], 'Legacy audio must not gain cloud upload authorization'
        assert before['audio']==after['audio']
        checks.append('actual_'+baseline+'_to_schema6_preserves_all_existing_columns_rows_and_audio')
        if baseline=='rc1':
            rejected=run('rc1-probe','open',upgrade,False)
            assert '资料库来自更新版本' in rejected.stdout and snapshot(upgrade)==after
            checks.append('released_rc1_refuses_schema6_without_content_change')
            restored=parent/'explicit-rollback-restore'
            shutil.copytree(backup,restored)
            run('rc1-probe','open',restored)
            assert snapshot(restored)==before and snapshot(upgrade)==after
            checks.append('explicit_preupgrade_copy_opens_in_rc1_while_rc2_data_is_preserved')
    crash=parent/'crash'
    killed('crash-seed',crash,'receipt.json',True)
    run('probe','verify',crash);checks.append('wal_durable_data_and_nonreplay_after_sigkill')
    killed('crash-transaction',crash,'transaction-ready')
    run('probe','verify',crash);checks.append('uncommitted_transaction_rolled_back_after_sigkill')
    killed('crash-delete',crash,'delete-ready')
    run('probe','verify-delete',crash);checks.append('erasure_intent_survives_sigkill_without_losing_text')
report={'scope':'Real SIGKILL subprocess; compiled released Beta/RC1 storage-source upgrade and explicit preupgrade-copy rollback; synthetic temporary data only','checks':checks,'passed':len(checks),'status':'PASS','baseline_revisions':{tag:subprocess.check_output(['git','rev-parse',tag],cwd=ROOT,text=True).strip() for tag in ['v1.0.0-beta.1','v1.0.0-rc.1']},'probe_sha256':hashlib.sha256((SCRATCH/'probe').read_bytes()).hexdigest(),'source_revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'source_dirty':bool(subprocess.check_output(['git','status','--porcelain','--','Sources','tests/fixtures/StoreProcessProbe.swift'],cwd=ROOT,text=True).strip())}
args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('RC_STORAGE_PROCESS_PASS',len(checks),'checks')
