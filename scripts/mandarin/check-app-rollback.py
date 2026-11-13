#!/usr/bin/env python3
"""Open an isolated synthetic archive with the installed, candidate, and installed apps, offline."""
import argparse
import array
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import sqlite3
import subprocess
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[2]
NETWORK_DENIED = ["sandbox-exec", "-p", "(version 1)(allow default)(deny network*)"]
TABLES = ("recordings", "revisions", "editing_drafts", "chunks", "transcript_timeline",
          "archive_draft_bases", "recording_cloud_authorizations", "dispatches", "recognition_candidates")


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=75)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} exited {result.returncode}: {result.stderr[-1200:]}")
    return result.stdout


def digest(data):
    return hashlib.sha256(data).hexdigest()


def binary_info(app):
    meta = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    run("codesign", "--verify", "--strict", app)
    return dict(bundle_id=meta["CFBundleIdentifier"], source=meta["SaytileSourceRevision"],
                version=meta["CFBundleShortVersionString"], build=meta["CFBundleVersion"],
                executable_sha256=digest((app / "Contents/MacOS/Saytile").read_bytes()))


def open_fixture(app, store, expected_count):
    store.mkdir(exist_ok=True)
    stdout = run(*NETWORK_DENIED, app / "Contents/MacOS/Saytile", "--data-directory", store, "--smoke-test")
    counts = re.findall(r"^SAYTILE_SMOKE_OK records=(\d+) ", stdout, flags=re.M)
    assert counts == [str(expected_count)], stdout


def profile_contract(app, tmp, info):
    # Compile only the exact bundle's Foundation-only storage-profile source.
    # Use its signed Info.plist as the basis for resolving Bundle.main in a helper.
    profile_path = "Sources/SaytileKit/SaytileStorageProfile.swift"
    source = run("git", "-C", ROOT, "show", info["source"] + ":" + profile_path)
    (tmp / "profile.swift").write_text(source)
    (tmp / "main.swift").write_text('''import Foundation
let profile = SaytileStorageProfile.current
let values = ["bundle": Bundle.main.bundleIdentifier!, "archive": profile.archiveDirectory.lastPathComponent,
              "byok_service": profile.byokService, "hosted_service": profile.hostedService]
print(String(decoding: try JSONEncoder().encode(values), as: UTF8.self))
''')
    helper = tmp / "Contract.app/Contents"
    (helper / "MacOS").mkdir(parents=True)
    plist = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    plist["CFBundleExecutable"] = "Contract"
    (helper / "Info.plist").write_bytes(plistlib.dumps(plist))
    exe = helper / "MacOS/Contract"
    run("swiftc", "-swift-version", "6", "-module-cache-path", tmp.parent / "module-cache",
        tmp / "profile.swift", tmp / "main.swift", "-o", exe)
    result = json.loads(run(*NETWORK_DENIED, exe))
    assert result["bundle"] == info["bundle_id"]
    return result


def seed(data, probe):
    for index in (1, 2):
        run(*NETWORK_DENIED, probe, "seed-beta", data)
        record = json.loads((data / "receipt.json").read_text())["record"]
        # The process fixture reserves a one-second file. Give it a real, deterministic WAV.
        path = data / "Audio" / record / "fixture.wav"
        samples = array.array("h", (((n * (61 + index)) % 2000) - 1000 for n in range(16000)))
        with wave.open(str(path), "wb") as wav:
            wav.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
            wav.writeframes(samples.tobytes())


def snapshot(data, count):
    with sqlite3.connect((data / "Saytile.sqlite").as_uri() + "?mode=ro", uri=True) as db:
        assert db.execute("PRAGMA integrity_check").fetchone() == ("ok",)
        assert not db.execute("PRAGMA foreign_key_check").fetchall()
        rows = {name: db.execute("SELECT * FROM " + name + " ORDER BY rowid").fetchall() for name in TABLES}
        schema = db.execute("PRAGMA user_version").fetchone()[0]
        edit = db.execute("""SELECT r.id,v.id,v.text,d.text,r.pinned,r.total_frames,r.audio_state
                              FROM recordings r JOIN revisions v ON v.id=r.preferred_revision
                              JOIN editing_drafts d ON d.recording_id=r.id
                              WHERE v.origin='userEdit' ORDER BY r.id""").fetchall()
        assert len(edit) == count and all(r[2:] == ("升级修改稿", "独立草稿待继续", 1, 16000, "available") for r in edit)
        assert len(rows["revisions"]) == 2 * count and len(rows["transcript_timeline"]) == count
        assert len(rows["recordings"]) == count and not rows["recording_cloud_authorizations"]
    audio = {}
    for _, _, rel, frames, _ in rows["chunks"]:
        path = data / "Audio" / rel
        with wave.open(str(path)) as wav:
            assert wav.getnframes() == frames == 16000 and wav.getframerate() == 16000
            audio[rel] = digest(path.read_bytes())
    assert len(set(audio.values())) == count
    return dict(schema=schema, table_sha256=digest(json.dumps(rows, sort_keys=True).encode()),
                row_counts={k: len(v) for k, v in rows.items()}, wav_sha256=audio,
                preferred_manual_revision_ids=[r[1] for r in edit], integrity="ok", foreign_key_errors=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("old", "candidate", "seed-probe", "output"):
        parser.add_argument("--" + key, required=True, type=Path)
    parser.add_argument("--same-candidate-profile", action="store_true", help="Upgrade and reopen the isolated candidate, never the production profile")
    args = parser.parse_args()
    apps = (args.old.resolve(), args.candidate.resolve())
    identities = [binary_info(app) for app in apps]
    assert identities[0]["bundle_id"] == ("app.saytile.mac.mandarin-candidate" if args.same_candidate_profile else "app.saytile.mac")
    if args.same_candidate_profile:
        assert int(identities[1]["build"]) > int(identities[0]["build"])
    assert identities[1]["bundle_id"] == "app.saytile.mac.mandarin-candidate"
    with tempfile.TemporaryDirectory(prefix="saytile-mandarin-rollback-") as folder:
        tmp = Path(folder).resolve()
        installed = []
        profiles = []
        for index, app in enumerate(apps):
            dest = tmp / str(index)
            dest.mkdir()
            installed.append(dest / app.name)
            run("cp", "-cR", app, installed[-1])
            assert binary_info(installed[-1]) == identities[index]
            profiles.append(profile_contract(installed[-1], dest, identities[index]))
        for key in ("archive", "byok_service", "hosted_service"):
            assert (profiles[0][key] == profiles[1][key]) == args.same_candidate_profile, key

        archive, upgrade, fresh = (tmp / key for key in ("original-fixture", "test-copy", "empty-candidate"))
        open_fixture(installed[0], archive, 0)
        seed(archive, args.seed_probe.resolve())
        open_fixture(installed[0], archive, 2)
        initial = snapshot(archive, 2)
        shutil.copytree(archive, upgrade)
        open_fixture(installed[1], fresh, 0)
        snapshot(fresh, 0)
        steps = []
        for label, app in (("old", installed[0]), ("candidate", installed[1]), ("old_reopened", installed[0])):
            open_fixture(app, upgrade, 2)
            state = snapshot(upgrade, 2)
            assert state == initial, label
            steps.append(dict(step=label, records=2, logical_tables_sha256=state["table_sha256"],
                              wav_sha256=sorted(state["wav_sha256"].values())))
        assert snapshot(archive, 2) == initial
    assert identities == [binary_info(app) for app in apps]
    result = dict(status="PASS", identities=identities, app_storage_profiles=profiles, fixture=initial, steps=steps,
                  network="denied to all smoke and probe processes", launch="explicit diagnostic directory, no capture or inference",
                  keychain="service names evaluated from the two exact sources using each signed bundle's identity; no secret inspected",
                  empty_candidate_records=0, original_fixture_unchanged=True, installed_binaries_unchanged=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
