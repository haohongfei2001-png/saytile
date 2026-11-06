#!/usr/bin/env python3
"""Measure an actual packaged app at idle. Dedicated empty data; no microphone or windows."""
import argparse, hashlib, json, pathlib, plistlib, signal, subprocess, tempfile, time
p=argparse.ArgumentParser();p.add_argument('--app',required=True,type=pathlib.Path);p.add_argument('--seconds',type=int,default=300);p.add_argument('--output',type=pathlib.Path,default=pathlib.Path('evidence/rc/app-idle.json'))
p.add_argument('--expected-source',required=True);p.add_argument('--expected-version',required=True);p.add_argument('--expected-binary-sha256',required=True);a=p.parse_args()
assert 10 <= a.seconds <= 7200
app=a.app.resolve(); binary=app/'Contents/MacOS/Saytile'; info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest()
assert info.get('SaytileSourceDirty') is False,'Idle candidate has uncommitted runtime sources'
assert info.get('SaytileSourceRevision')==a.expected_source,'Idle candidate source does not match expected source'
assert info.get('SaytileReleaseVersion')==a.expected_version,'Idle candidate release does not match expected version'
assert binary_sha256==a.expected_binary_sha256,'Idle candidate binary does not match intended DMG executable'
with tempfile.TemporaryDirectory(prefix='saytile-idle-') as temp:
    directory=pathlib.Path(temp); log=directory/'time.log'
    with log.open('w') as stream:
        process=subprocess.Popen(['/usr/bin/time','-l',str(binary),'--data-directory',str(directory/'data')],stdout=stream,stderr=stream)
        child=None
        for _ in range(30):
            children=subprocess.run(['pgrep','-P',str(process.pid)],capture_output=True,text=True).stdout.split()
            if children: child=int(children[0]);break
            time.sleep(.1)
        if child is None: process.kill();raise RuntimeError('Packaged app failed to start')
        samples=[]; start=time.monotonic()
        try:
            while time.monotonic()-start < a.seconds:
                if process.poll() is not None: raise RuntimeError('Packaged idle app terminated unexpectedly')
                sample=subprocess.check_output(['ps','-p',str(child),'-o','rss=,%cpu='],text=True).split()
                samples.append({'seconds':round(time.monotonic()-start,3),'rssKiB':int(sample[0]),'cpuPercent':float(sample[1])})
                time.sleep(min(5,max(.01,a.seconds-(time.monotonic()-start))))
        finally:
            if process.poll() is None:
                subprocess.run(['kill','-TERM',str(child)],check=False)
            process.wait(timeout=10)
    output=log.read_text();a.output.parent.mkdir(parents=True,exist_ok=True);a.output.with_suffix('.log').write_text(output)
    isolation='SAYTILE_ISOLATED_LAUNCH cloud_enabled=false automatic_recovery=false shortcut=disabled visible_panel=false hotkey_registered=false'
    assert isolation in output,'Idle process did not confirm isolated preferences and disabled recovery/UI/shortcut'
    warm_samples=[s for s in samples if s['seconds']>=10]
    report={'scope':'Packaged app idle, menu-bar timer and AppModel refresh, empty isolated database and ephemeral preferences, no microphone, no ASR, no windows or global shortcut; ends by intentional SIGTERM','source_revision':info.get('SaytileSourceRevision'),'source_dirty':info.get('SaytileSourceDirty'),'binary_sha256':binary_sha256,'release_version':info.get('SaytileReleaseVersion'),'expected_source_revision':a.expected_source,'expected_release_version':a.expected_version,'expected_binary_sha256':a.expected_binary_sha256,'isolated_preferences_confirmed':True,'wall_seconds':round(time.monotonic()-start,3),'rss_min_kib':min(s['rssKiB'] for s in samples),'warm_rss_min_kib':min((s['rssKiB'] for s in warm_samples),default=None),'warm_rss_max_kib':max((s['rssKiB'] for s in warm_samples),default=None),'final_rss_kib':samples[-1]['rssKiB'],'rss_max_kib':max(s['rssKiB'] for s in samples),'samples':samples,'not_measured':'whole-system energy and Apple speech service activity'}
    a.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='samples'},indent=2))
