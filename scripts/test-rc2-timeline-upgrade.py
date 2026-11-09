#!/usr/bin/env python3
"""Rehearse the signed no-api.10 upgrade in a disposable installation; never launch a default data domain."""
import argparse
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import sqlite3
import subprocess
import tempfile
from uuid import uuid4
import wave

ROOT = Path(__file__).resolve().parents[1]
OLD_HASH = '62e0054ea9372d149c353ddc0f44f5e341b3a7d68d5b78c1f0c5a9d656e5154f'
OLD = next((ROOT / 'deliverables/no-api.10').glob('*.dmg'))


def run(*args, check=True):
    return subprocess.run(list(map(str, args)), capture_output=True, text=True, check=check, timeout=180)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


@contextmanager
def mount(image, path):
    path.mkdir()
    run('hdiutil', 'verify', image)
    run('hdiutil', 'attach', '-nobrowse', '-readonly', '-mountpoint', path, image)
    try:
        yield path / 'Saytile.app'
    finally:
        run('hdiutil', 'detach', path)


def info(app):
    return plistlib.loads((app / 'Contents/Info.plist').read_bytes())


def requirement(app):
    run('codesign', '--verify', '--strict', app)
    return run('codesign', '-dr', '-', app).stderr.split('designated => ')[1].strip()


def probe(source, scratch, exe, identity):
    build = ['swift', 'build', '--package-path', source, '--scratch-path', scratch, '-c', 'release', '--product', 'SaytileKit']
    run(*build)
    lib = Path(run(*build, '--show-bin-path').stdout.strip())
    module = lib / '../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap'
    if not module.exists():
        module = lib / 'CAudio.build/module.modulemap'
    run('swiftc', '-swift-version', '6', '-parse-as-library', '-I', lib, '-I', lib / 'Modules',
        '-I', source / 'Sources/CSQLite', '-Xcc', '-fmodule-map-file=' + str(module),
        '-L', lib, '-lSaytileKit', '-lc++', ROOT / 'tests/fixtures/RC2UpgradeContinuity.swift', '-o', exe)
    run('codesign', '--force', '--timestamp=none', '-i', 'app.saytile.tests.rc2-upgrade', '--sign', identity, exe)


def smoke(app, data):
    assert 'SAYTILE_SMOKE_OK' in run(app / 'Contents/MacOS/Saytile', '--data-directory', data, '--smoke-test').stdout


def seed_media(data, fixture):
    with sqlite3.connect(data / 'Saytile.sqlite') as db:
        for rid in [fixture['allowed'], fixture['localOnly']]:
            cid = str(uuid4()).upper()
            media = data / 'Audio' / rid / (cid + '.wav')
            media.parent.mkdir()
            with wave.open(str(media), 'wb') as wav:
                wav.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                wav.writeframes(b'\x01\x00' * 3200)
            db.execute('INSERT INTO chunks VALUES (?,?,?,3200,0)', (cid, rid, str(media.relative_to(data / 'Audio'))))
            for origin, text in [('final', '合成的原话'), ('userEdit', '用户修订的原话')]:
                vid = str(uuid4()).upper()
                db.execute('INSERT INTO revisions(id,recording_id,text,origin,created_at) VALUES (?,?,?,?,1)', (vid, rid, text, origin))
            db.execute("UPDATE recordings SET preferred_revision=?,pinned=1,recognition_state='completed' WHERE id=?", (vid, rid))
            db.execute("INSERT INTO editing_drafts VALUES (?, '单独保存的草稿',1)", (rid,))
        # First utterance is 0.2ms before UTC midnight. The next utterance is on the next day.
        for rid, start in [(fixture['allowed'], 1735775999.9998), (fixture['localOnly'], 1735776000.1)]:
            db.execute("UPDATE recordings SET created_at=? WHERE id=?", (start, rid))


def snapshot(data):
    with sqlite3.connect(data / 'Saytile.sqlite') as db:
        assert db.execute('PRAGMA quick_check').fetchone() == ('ok',) and not db.execute('PRAGMA foreign_key_check').fetchall()
        tables = ['recordings', 'chunks', 'revisions', 'editing_drafts', 'recording_cloud_authorizations', 'dispatches']
        rows = {name: db.execute('SELECT * FROM ' + name + ' ORDER BY rowid').fetchall() for name in tables}
        return db.execute('PRAGMA user_version').fetchone()[0], rows, {str(p.relative_to(data)): sha(p) for p in (data/'Audio').rglob('*.wav')}


def rehearse(dmg, expected, scratch):
    assert sha(OLD) == OLD_HASH
    identities = re.findall(r'\b([0-9A-F]{40}) "Developer ID Application:', run('security', 'find-identity', '-v', '-p', 'codesigning').stdout)
    assert len(identities) == 1
    with tempfile.TemporaryDirectory(prefix='saytile-rc2-continuity-') as raw:
        tmp = Path(raw)
        data, fixture = tmp/'data', tmp/'fixture.json'
        data.mkdir()
        with mount(OLD, tmp/'old-mount') as old, mount(dmg, tmp/'new-mount') as new:
            prior, candidate = info(old), info(new)
            req = requirement(old)
            assert requirement(new) == req and prior['CFBundleIdentifier'] == candidate['CFBundleIdentifier'] == 'app.saytile.mac'
            signature = run('codesign', '-dv', '--verbose=4', new).stderr
            assert 'Authority=Developer ID Application:' in signature and 'runtime' in signature and 'Timestamp=' in signature
            for app in (old, new):
                entitlements = subprocess.check_output(['codesign','-d','--entitlements',':-',app], stderr=subprocess.DEVNULL)
                assert plistlib.loads(entitlements) == {'com.apple.security.device.audio-input': True}
            assert not candidate['SaytileSourceDirty'] and candidate['SaytileSourceRevision'] == expected
            assert int(candidate['CFBundleVersion']) > int(prior['CFBundleVersion'])
            run('codesign','--verify','--strict','-R',req,new)
            run('codesign','--verify','--strict',dmg)
            installed = tmp/'Applications/Saytile.app'
            installed.parent.mkdir()
            run('ditto','--norsrc',old,installed)
            smoke(installed, data)
            legacy = tmp/'legacy'
            legacy.mkdir()
            archive = tmp/'legacy.tar'
            run('git','-C',ROOT,'archive',prior['SaytileSourceRevision'],'-o',archive,'Package.swift','Sources','tests/SaytileKitTests')
            run('tar','-xf',archive,'-C',legacy)
            oldprobe, newprobe = tmp/'old-probe', tmp/'new-probe'
            probe(legacy, tmp/'build-old', oldprobe, identities[0])
            probe(ROOT, scratch, newprobe, identities[0])
            try:
                run(oldprobe, 'seed', data, fixture)
                seed_media(data, json.loads(fixture.read_text()))
                smoke(installed, data)
                run(oldprobe, 'verify', data, fixture)
                before = snapshot(data)
                assert before[0] == 5 and len(before[2]) == 2 and len(before[1]['recording_cloud_authorizations']) == 2
                backup = tmp/'v5-backup'
                shutil.copytree(data, backup)
                shutil.rmtree(installed)
                run('ditto','--norsrc',new,installed)
                smoke(installed, data)
                after = snapshot(data)
                assert after[0] == 6 and before[1:] == after[1:]
                with sqlite3.connect(data/'Saytile.sqlite') as db:
                    assert db.execute('SELECT day,position=group_start FROM transcript_timeline ORDER BY position').fetchall() == [('2025-01-01',1),('2025-01-02',1)]
                continuity = run(newprobe, 'verify', data, fixture).stdout.strip()
                smoke(installed, data)
                assert snapshot(data) == after
                rejected = run(old/'Contents/MacOS/Saytile','--data-directory',data,'--smoke-test',check=False)
                assert rejected.returncode != 0 and '资料库来自更新版本' in rejected.stdout and snapshot(data) == after
                smoke(old, backup)
                assert snapshot(backup) == before
                cloud_scopes = len(before[1]['recording_cloud_authorizations'])
                sp = run('spctl','--assess','--type','execute','--verbose=4',installed,check=False)
            finally:
                if fixture.exists():
                    run(oldprobe, 'cleanup', data, fixture)
            return dict(status='PASS', source=expected, old_source=prior['SaytileSourceRevision'], old_dmg=OLD_HASH,
                        candidate_dmg=sha(dmg), candidate_executable=sha(installed/'Contents/MacOS/Saytile'),
                        bundle_id=candidate['CFBundleIdentifier'], old_build=prior['CFBundleVersion'], new_build=candidate['CFBundleVersion'],
                        matching_developer_id_requirement=True, hardened_runtime=True, trusted_timestamp=True, identical_entitlements=True, schema=[5,6], wav_hashes_preserved=len(before[2]),
                        preserved_versions=len(before[1]['revisions']), preserved_drafts=len(before[1]['editing_drafts']),
                        existing_cloud_scopes=cloud_scopes, midnight_split=True, no_new_grants=True,
                        keychain=continuity, keychain_scope='Separate v5/v6 probes signed with the same test identity; exact production libraries, random synthetic accounts only. Actual apps separately satisfy the frozen designated requirement.',
                        restarts=True, downgrade_refused=True, backup_rollback=True, cleanup=True,
                        gatekeeper=dict(status='PASS' if sp.returncode == 0 else 'FAIL', reason=sp.stderr.strip().splitlines()[-1]),
                        live_services='NOT_RUN')


if __name__ == '__main__':
    import os
    import time
    parser = argparse.ArgumentParser()
    parser.add_argument('--dmg', required=True, type=Path)
    parser.add_argument('--source', required=True)
    parser.add_argument('--scratch', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    os.environ['TZ'] = 'UTC'
    time.tzset()
    assert run('git','-C',ROOT,'diff','--quiet',args.source,'--','Sources','Package.swift','packaging').returncode == 0
    result = rehearse(args.dmg.resolve(), args.source, args.scratch.resolve())
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(result, ensure_ascii=False))
