#!/usr/bin/env python3
"""Verify DMG installation and actual Beta-to-RC app/data upgrade in a disposable location."""
import argparse, hashlib, json, os, pathlib, plistlib, shutil, sqlite3, subprocess, tempfile, time
p=argparse.ArgumentParser();p.add_argument('--dmg',required=True,type=pathlib.Path);p.add_argument('--beta-dmg',required=True,type=pathlib.Path);p.add_argument('--output',type=pathlib.Path,default=pathlib.Path('evidence/rc/install-upgrade.json'));a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]; checks=[]; logs=[]
def run(args, expected=0, timeout=60):
    r=subprocess.run([str(x) for x in args],capture_output=True,text=True,timeout=timeout,cwd=root)
    logs.append(r.stdout+r.stderr)
    if r.returncode!=expected: raise RuntimeError(f'{args[0]} exit={r.returncode}: {r.stdout}\n{r.stderr}')
    return r

def snapshot(directory):
    with sqlite3.connect(directory/'Saytile.sqlite') as db:
        return {'records':db.execute('select id,preferred_revision,pinned,audio_state,is_recording from recordings order by id').fetchall(),'versions':db.execute('select id,recording_id,text from revisions order by id').fetchall(),'drafts':db.execute('select recording_id,text from editing_drafts').fetchall(),'dispatches':db.execute('select id,state,text from dispatches').fetchall(),'integrity':db.execute('pragma quick_check').fetchone()[0],'schema':db.execute('pragma user_version').fetchone()[0]}

def app_start(app,data):
    start=time.monotonic(); r=run([app/'Contents/MacOS/Saytile','--data-directory',data,'--smoke-test'],timeout=30)
    assert 'SAYTILE_SMOKE_OK' in r.stdout
    return round(time.monotonic()-start,3)

with tempfile.TemporaryDirectory(prefix='saytile-install-upgrade-') as temp:
    temp=pathlib.Path(temp); mount=temp/'mount'; mount.mkdir(); install=temp/'Applications';install.mkdir(); app=install/'Saytile.app'; data=temp/'data'
    old=temp/'old-source';old.mkdir()
    for name in ('Models.swift','Store.swift','StoreSQLite.swift'):
        (old/name).write_bytes(subprocess.check_output(['git','show',f'v1.0.0-beta.1:Sources/SaytileKit/{name}'],cwd=root))
    writer=temp/'beta-writer'
    run(['swiftc','-O','-swift-version','6','-parse-as-library','-I','Sources/CSQLite',*(old/n for n in ('Models.swift','Store.swift','StoreSQLite.swift')),'tests/fixtures/StoreProcessProbe.swift','-o',writer])
    run([writer,'seed-beta',data]);checks.append('seeded_using_actual_released_beta_storage_source')
    timings=[]
    for label,dmg in [('beta',a.beta_dmg),('rc',a.dmg)]:
        run(['hdiutil','verify',dmg.resolve()]);run(['hdiutil','attach','-readonly','-nobrowse','-mountpoint',mount,dmg.resolve()])
        try:
            source=mount/'Saytile.app';run(['codesign','--verify','--strict',source])
            if app.exists(): shutil.rmtree(app)
            run(['ditto','--norsrc',source,app]);run(['codesign','--verify','--strict',app])
        finally: run(['hdiutil','detach',mount])
        timings.append({label+'_startup_seconds':app_start(app,data)})
        if label=='beta': before=snapshot(data);checks.append('beta_app_installed_signed_and_started_on_seeded_data')
        else:
            after=snapshot(data);assert before['schema']==1 and after['schema']==2
            assert all(after[k]==before[k] for k in ('records','versions','drafts','dispatches'))
            assert after['integrity']=='ok';checks.append('rc_app_upgrade_preserves_records_versions_drafts_dispatches')
    for _ in range(3): timings.append({'rc_restart_seconds':app_start(app,data)})
    assert snapshot(data)==after;checks.append('three_normal_restarts_preserve_data_and_uncertain_dispatch')
    owner=subprocess.Popen([str(app/'Contents/MacOS/Saytile'),'--data-directory',str(data),'-hasLaunched','YES','-shortcutChoice','disabled'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        time.sleep(1);assert owner.poll() is None
        rejected=run([app/'Contents/MacOS/Saytile','--data-directory',data,'--smoke-test'],expected=1)
        assert '另一个 Saytile' in rejected.stdout;checks.append('second_packaged_process_rejected_without_modal_prompt')
    finally: owner.terminate();owner.wait(timeout=10)
    app_start(app,data);assert snapshot(data)==after;checks.append('restart_after_forced_process_exit_retains_upgrade_data')
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert info.get('SaytileSourceDirty') is False
    report={'status':'PASS','checks':checks,'count':len(checks),'startup_timings':timings,'source_revision':info['SaytileSourceRevision'],'release_version':info['SaytileReleaseVersion'],'dmg_sha256':hashlib.sha256(a.dmg.read_bytes()).hexdigest(),'scope':'Readonly DMG signature, independent installation, actual Beta app and RC app startup/upgrade, immutable synthetic content comparison, duplicate-instance rejection; no real user database or microphone'}
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');a.output.with_suffix('.log').write_text('\n'.join(logs));print(json.dumps(report,ensure_ascii=False,indent=2))
