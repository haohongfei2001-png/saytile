"""Read-only DMG mounts, synthetic v5 archive, independent installed copy and rollback."""
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid
import wave

root = Path(__file__).resolve().parents[2]
old = next((root / 'deliverables/no-api.10').glob('*.dmg'))
dmg = root / 'deliverables/timeline-preview/Saytile-Timeline-Preview-arm64.dmg'
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)
def run(*args, check=True):
    return subprocess.run(args, capture_output=True, text=True, check=check, timeout=75)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
@contextmanager
def mount(image, dest):
    dest.mkdir()
    run('hdiutil','verify',image)
    run('hdiutil','attach','-nobrowse','-readonly','-mountpoint',dest,image)
    try:
        yield next(dest.glob('*.app'))
    finally:
        run('hdiutil','detach',dest)
def smoke(app, path):
    return 'SAYTILE_SMOKE_OK' in run(app/'Contents/MacOS/Saytile','--data-directory',path,'--smoke-test').stdout
def snapshot(path):
    with sqlite3.connect(path / 'Saytile.sqlite') as db:
        schema = db.execute('pragma user_version').fetchone()[0]
        assert db.execute('pragma quick_check').fetchone() == ('ok',)
        queries = ['recordings','revisions','editing_drafts','chunks','dispatches','recording_cloud_authorizations']
        tables = [db.execute('select * from '+t+' order by rowid').fetchall() for t in queries]
    return schema, tables, [sha(f) for f in sorted((path/'Audio').rglob('*.wav'))]
def seed(path):
    ids = [str(uuid.uuid4()).upper() for _ in range(4)]
    rid,vid1,vid2,cid = ids
    audio = path/'Audio'/rid/(cid+'.wav')
    audio.parent.mkdir()
    with wave.open(str(audio),'wb') as wav:
        wav.setparams((1,2,16000,16000,'NONE','not compressed'))
        wav.writeframes(b'\0\0'*16000)
    with sqlite3.connect(path/'Saytile.sqlite') as db:
        db.execute("INSERT INTO recordings(id,created_at,sample_rate,preferred_revision,pinned,is_recording,recognition_state) VALUES (?,1700000000,16000,?,1,0,'completed')",(rid,vid2))
        for vid,text,origin in [(vid1,'先保留原话','final'),(vid2,'我改过的原话','userEdit')]:
            db.execute('INSERT INTO revisions(id,recording_id,text,origin,created_at) VALUES (?,?,?,?,1700000000)',(vid,rid,text,origin))
        db.execute('INSERT INTO editing_drafts VALUES (?,?,1700000000)',(rid,'尚未提交的草稿'))
        db.execute('INSERT INTO chunks VALUES (?,?,?,16000,0)',(cid,rid,str(audio.relative_to(path/'Audio'))))
with tempfile.TemporaryDirectory(prefix='saytile-timeline-install-') as raw:
    temp = Path(raw)
    old_data = temp/'old'
    with mount(old,temp/'old-mount') as previous:
        assert smoke(previous,old_data)
        seed(old_data)
        assert smoke(previous,old_data)
        before = snapshot(old_data)
        assert before[0] == 5 and len(before[2]) == 1
        # Never write the baseline image; both the backup and upgrade target are fixtures.
        copy = temp/'upgrade'
        shutil.copytree(old_data,copy)
        with mount(dmg,temp/'new-mount') as preview:
            app = output/'installed'/preview.name
            app.parent.mkdir(exist_ok=True)
            assert not app.exists()
            run('ditto','--norsrc',preview,app)
            run('codesign','--verify','--strict',app)
            run('codesign','--verify','--strict',dmg)
            assert smoke(app,copy)
            after = snapshot(copy)
            assert after[0] == 6 and before[1:] == after[1:]
            with sqlite3.connect(copy/'Saytile.sqlite') as db:
                assert db.execute('select count(*) from transcript_timeline where position=group_start').fetchone() == (1,)
            assert smoke(app,copy) and snapshot(copy)==after
            info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
            signature = run('codesign','-dv','--verbose=4',app).stderr
            assert 'Authority=Developer ID Application' in signature and 'runtime' in signature and 'Timestamp=' in signature
            sp = run('spctl','--assess','--type','execute','--verbose=4',app,check=False)
            assert not info['SaytileSourceDirty'] and info['CFBundleIdentifier'] == 'app.saytile.mac.timeline-preview'
        rollback = temp / 'rollback'
        shutil.copytree(old_data,rollback)
        assert smoke(previous,rollback) and snapshot(rollback)==before
    receipt = dict(status='PASS', source_revision=info['SaytileSourceRevision'], source_dirty=False,
                   tree=run('git','-C',root,'rev-parse',info['SaytileSourceRevision']+'^{tree}').stdout.strip(),
                   release=info['SaytileReleaseVersion'], bundle=info['CFBundleIdentifier'], binary_sha256=sha(app/'Contents/MacOS/Saytile'),
                   dmg_sha256=sha(dmg), baseline_dmg_sha256=sha(old), developer_id=True, hardened_runtime=True, timestamp=True,
                   gatekeeper=dict(status='PASS' if sp.returncode==0 else 'FAIL', exit=sp.returncode, result=sp.stderr.strip().splitlines()[-1]),
                   checks=['DMGs verified and read-only mounted','private installation and signature validation','actual RC2 v5 archive startup','v6 upgrade with byte-identical WAV, revisions, draft, preferred version, pin and cloud scopes','projection correct','idempotent second launch','rollback from separate v5 backup'])
    (output/'package-identity.json').write_text(json.dumps(receipt, indent=2)+'\n')
    print(json.dumps(receipt, indent=2))
