#!/usr/bin/env python3
"""Verify packaged-app upgrade, downgrade refusal and snapshot rollback in a disposable location."""
import argparse, hashlib, json, os, pathlib, plistlib, shutil, sqlite3, subprocess, sys, tempfile, time
p=argparse.ArgumentParser()
p.add_argument('--dmg',required=True,type=pathlib.Path)
p.add_argument('--previous-dmg','--beta-dmg',dest='previous_dmg',required=True,type=pathlib.Path)
p.add_argument('--baseline-ref',choices=['v1.0.0-beta.1','v1.0.0-rc.1'])
p.add_argument('--expected-source',required=True,help='Exact committed candidate source revision')
p.add_argument('--expected-version',required=True,help='Exact candidate release version')
p.add_argument('--expected-binary-sha256',required=True,help='Executable hash from the intended candidate DMG')
p.add_argument('--output',type=pathlib.Path,default=pathlib.Path('research/asr/validation/rc2/install-upgrade.json'))
a=p.parse_args()
a.baseline_ref=a.baseline_ref or ('v1.0.0-beta.1' if '--beta-dmg' in sys.argv else 'v1.0.0-rc.1')
expected_schema=1 if a.baseline_ref=='v1.0.0-beta.1' else 2
root=pathlib.Path(__file__).resolve().parents[1]; checks=[]; logs=[]
def run(args, expected=0, timeout=60):
    r=subprocess.run([str(x) for x in args],capture_output=True,text=True,timeout=timeout,cwd=root)
    logs.append(r.stdout+r.stderr)
    if r.returncode!=expected: raise RuntimeError(f'{args[0]} exit={r.returncode}: {r.stdout}\n{r.stderr}')
    return r

def snapshot(directory):
    with sqlite3.connect(directory/'Saytile.sqlite') as db:
        cloud_authorizations = db.execute('select * from recording_cloud_authorizations order by recording_id').fetchall() if db.execute("select 1 from sqlite_master where type='table' and name='recording_cloud_authorizations'").fetchone() else None
        return {'records':db.execute('select id,preferred_revision,pinned,audio_state,is_recording from recordings order by id').fetchall(),'versions':db.execute('select id,recording_id,text from revisions order by id').fetchall(),'drafts':db.execute('select recording_id,text from editing_drafts').fetchall(),'dispatches':db.execute('select id,state,text from dispatches').fetchall(),'integrity':db.execute('pragma quick_check').fetchone()[0],'schema':db.execute('pragma user_version').fetchone()[0], 'cloud_authorizations':cloud_authorizations, 'audio':{str(x.relative_to(directory)):hashlib.sha256(x.read_bytes()).hexdigest() for x in (directory/'Audio').rglob('*') if x.is_file()}}

def app_start(app,data):
    start=time.monotonic(); r=run([app/'Contents/MacOS/Saytile','--data-directory',data,'--smoke-test'],timeout=30)
    assert 'SAYTILE_SMOKE_OK' in r.stdout
    return round(time.monotonic()-start,3)

with tempfile.TemporaryDirectory(prefix='saytile-install-upgrade-') as temp:
    temp=pathlib.Path(temp); mount=temp/'mount'; mount.mkdir(); install=temp/'Applications';install.mkdir(); app=install/'Saytile.app'; data=temp/'data'
    old=temp/'old-source';old.mkdir()
    names=['Models.swift','Store.swift','StoreSQLite.swift']
    if expected_schema==2: names.append('StoreLock.swift')
    for name in names:
        (old/name).write_bytes(subprocess.check_output(['git','show',f'{a.baseline_ref}:Sources/SaytileKit/{name}'],cwd=root))
    writer=temp/'beta-writer'
    run(['swiftc','-O','-swift-version','6','-parse-as-library','-I','Sources/CSQLite',*(old/n for n in names),'tests/fixtures/StoreProcessProbe.swift','-o',writer])
    run([writer,'seed-beta',data]);checks.append('seeded_using_actual_released_baseline_storage_source')
    timings=[]
    for label,dmg in [('previous',a.previous_dmg),('candidate',a.dmg)]:
        run(['hdiutil','verify',dmg.resolve()]);run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',mount,dmg.resolve()])
        try:
            source=mount/'Saytile.app';run(['codesign','--verify','--strict',source])
            if app.exists(): shutil.rmtree(app)
            run(['ditto','--norsrc',source,app]);run(['codesign','--verify','--strict',app])
        finally: run(['hdiutil','detach',mount])
        info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
        binary_sha256=hashlib.sha256((app/'Contents/MacOS/Saytile').read_bytes()).hexdigest()
        if label=='candidate':
            assert info.get('SaytileSourceDirty') is False,'Candidate has uncommitted runtime sources'
            assert info.get('SaytileSourceRevision')==a.expected_source,'Candidate source does not match expected source'
            assert info.get('SaytileReleaseVersion')==a.expected_version,'Candidate release does not match expected version'
            assert binary_sha256==a.expected_binary_sha256,'Candidate binary does not match the intended DMG executable'
            candidate_binary_sha256=binary_sha256
        else:
            previous_binary_sha256=binary_sha256
        timings.append({label+'_startup_seconds':app_start(app,data)})
        if label=='previous':
            previous_info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
            assert previous_info['SaytileReleaseVersion']==a.baseline_ref.removeprefix('v')
            before=snapshot(data); assert before['schema']==expected_schema
            previous_app=temp/'previous-app/Saytile.app'; previous_app.parent.mkdir()
            run(['ditto','--norsrc',app,previous_app])
            backup=temp/'pre-upgrade-data';shutil.copytree(data,backup)
            checks.append('released_app_installed_signed_and_started_on_seeded_data')
        else:
            after=snapshot(data);assert before['schema']==expected_schema and after['schema']==6
            assert after['cloud_authorizations'] == [], 'Upgrade must not authorize existing audio for upload'
            assert all(after[k]==before[k] for k in ('records','versions','drafts','dispatches','audio'))
            assert after['integrity']=='ok';checks.append('candidate_upgrade_preserves_records_versions_drafts_dispatches_and_audio')
    if expected_schema==2:
        rejected=run([previous_app/'Contents/MacOS/Saytile','--data-directory',data,'--smoke-test'],expected=1)
        assert '资料库来自更新版本' in rejected.stdout and snapshot(data)==after
        checks.append('released_rc1_app_refuses_new_schema_without_changing_content')
        restored=temp/'restored-pre-upgrade-data';shutil.copytree(backup,restored)
        app_start(previous_app,restored)
        assert snapshot(restored)==before and snapshot(data)==after
        checks.append('explicit_preupgrade_snapshot_restores_rc1_without_overwriting_candidate_data')
    for _ in range(3): timings.append({'rc_restart_seconds':app_start(app,data)})
    assert snapshot(data)==after;checks.append('three_normal_restarts_preserve_data_and_uncertain_dispatch')
    owner=subprocess.Popen([str(app/'Contents/MacOS/Saytile'),'--data-directory',str(data)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        time.sleep(1);assert owner.poll() is None
        rejected=run([app/'Contents/MacOS/Saytile','--data-directory',data,'--smoke-test'],expected=1)
        assert '另一个 Saytile' in rejected.stdout;checks.append('second_packaged_process_rejected_without_modal_prompt')
    finally:
        owner.terminate();owner_output,owner_error=owner.communicate(timeout=10)
        logs.append(owner_output+owner_error)
    isolation='SAYTILE_ISOLATED_LAUNCH cloud_enabled=false automatic_recovery=false shortcut=disabled visible_panel=false hotkey_registered=false'
    assert isolation in owner_output,'Held candidate process did not confirm isolated preferences and disabled recovery/UI/shortcut'
    app_start(app,data);assert snapshot(data)==after;checks.append('restart_after_forced_process_exit_retains_upgrade_data')
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert info.get('SaytileSourceDirty') is False
    report={'status':'PASS','checks':checks,'count':len(checks),'startup_timings':timings,'source_revision':info['SaytileSourceRevision'],'release_version':info['SaytileReleaseVersion'],'binary_sha256':candidate_binary_sha256,'expected_source_revision':a.expected_source,'expected_release_version':a.expected_version,'expected_binary_sha256':a.expected_binary_sha256,'held_candidate_preferences_isolated':True,'baseline_ref':a.baseline_ref,'baseline_app_source_revision':previous_info.get('SaytileSourceRevision'),'baseline_app_release_version':previous_info['SaytileReleaseVersion'],'baseline_binary_sha256':previous_binary_sha256,'baseline_revision':subprocess.check_output(['git','rev-parse',a.baseline_ref],cwd=root,text=True).strip(),'previous_dmg_sha256':hashlib.sha256(a.previous_dmg.read_bytes()).hexdigest(),'dmg_sha256':hashlib.sha256(a.dmg.read_bytes()).hexdigest(),'scope':'Readonly DMG signature, explicit candidate source/version/binary identity, independent installation, actual released app and candidate startup/upgrade, exact synthetic content/audio comparison, explicit copy rollback and duplicate-instance rejection; held candidate has ephemeral preferences with no cloud/recovery/shortcut/window; no real user database or microphone'}
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');a.output.with_suffix('.log').write_text('\n'.join(logs));print(json.dumps(report,ensure_ascii=False,indent=2))
