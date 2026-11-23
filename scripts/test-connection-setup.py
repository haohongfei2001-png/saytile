#!/usr/bin/env python3
"""Reject unsafe setup CLI invocations without opening a window or reading any API key."""
import argparse,hashlib,json,pathlib,plistlib,subprocess,tempfile
parser=argparse.ArgumentParser();parser.add_argument('--app',type=pathlib.Path,required=True)
parser.add_argument('--output',type=pathlib.Path,required=True);args=parser.parse_args()
app=args.app.resolve(); executable=app/'Contents/MacOS/Saytile' if app.suffix=='.app' else app
checks=[]
production=pathlib.Path.home()/'Library/Application Support/Saytile'
with tempfile.TemporaryDirectory(prefix='saytile-setup-cli-') as temporary:
    base=pathlib.Path(temporary);fresh=base/'fresh';fresh.mkdir();occupied=base/'occupied';occupied.mkdir();(occupied/'keep.txt').write_text('keep')
    for name,arguments in [
        ('missing_directory',['--connection-setup']),
        ('missing_output',['--connection-setup','--data-directory',str(fresh)]),
        ('output_outside_isolated_directory',['--connection-setup','--data-directory',str(fresh),'--connection-output',str(base/'outside.json')]),
        ('existing_data_directory',['--connection-setup','--data-directory',str(occupied),'--connection-output',str(occupied/'config.json')]),
        ('production_root',['--connection-setup','--data-directory',str(production),'--connection-output',str(production/'setup.json')]),
        ('production_subdirectory',['--connection-setup','--data-directory',str(production/'Audio/isolated-setup-probe'),'--connection-output',str(production/'Audio/isolated-setup-probe/setup.json')]),
        ('conflicting_probe',['--connection-setup','--data-directory',str(fresh),'--connection-output',str(fresh/'config.json'),'--device-probe']),
    ]:
        result=subprocess.run([str(executable),*arguments],text=True,capture_output=True,timeout=15)
        assert result.returncode==64,(name,result.returncode,result.stdout,result.stderr)
        assert not list(base.rglob('Saytile.sqlite')) and not list(base.rglob('*.json'))
        checks.append({'case':name,'exit':64,'result':'PASS_BEFORE_STORE_OR_WINDOW'})
    assert (occupied/'keep.txt').read_text()=='keep'
metadata=plistlib.loads((app/'Contents/Info.plist').read_bytes()) if app.suffix=='.app' else {}
report={'binary_sha256':hashlib.sha256(executable.read_bytes()).hexdigest(),'source_revision':metadata.get('SaytileSourceRevision'),'source_dirty':metadata.get('SaytileSourceDirty'),'packaged_bundle':app.suffix=='.app','passed':len(checks),'checks':checks,'window_opened':False,'microphone_started':False,'credential_values_read':False,'provider_requests':0}
args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n');print('CONNECTION_SETUP_CLI_PASS',len(checks),'cases')
