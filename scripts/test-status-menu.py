#!/usr/bin/env python3
"""Exercise the supplied native app's actual status item in a disposable identity."""
import argparse
from pathlib import Path
import plistlib
import sqlite3
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, required=True)
args = parser.parse_args()
source = args.app.resolve(strict=True)
subprocess.run(["codesign", "--verify", "--strict", str(source)], check=True)
fixture = Path(__file__).resolve().parents[1] / "tests/fixtures/StatusMenuProbe.swift"
with tempfile.TemporaryDirectory(prefix="menuprobe-", dir="/private/tmp") as tmp:
    work = Path(tmp)
    app = work / "Saytile.app"
    subprocess.run(["ditto", "--norsrc", str(source), str(app)], check=True)
    info = app / "Contents/Info.plist"
    values = plistlib.loads(info.read_bytes())
    assert values["CFBundleExecutable"] == "Saytile"
    values["CFBundleIdentifier"] = "app.saytile.test.menu." + work.name
    info.write_bytes(plistlib.dumps(values))
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
    probe = work / "menu-probe"
    subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library", str(fixture), "-o", str(probe)], check=True)
    with tempfile.TemporaryDirectory(prefix="menuprobetmp-", dir="/private/tmp") as environment_home:
        import os
        env = {**os.environ, "CFFIXED_USER_HOME": environment_home}
        # Check the actual Foundation on this Mac before running the normal launch
        # path with CFFIXED_USER_HOME, to keep all recordings inside the fixture.
        check = ["swift", "-e", 'import Foundation; print(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path)']
        result = subprocess.check_output(check, env=env, text=True).strip()
        assert Path(result).resolve() == Path(environment_home).resolve() / "Library/Application Support"
    subprocess.run([str(probe), str(app), str(work)], check=True, timeout=90)
    for database in [work / "new-data/Saytile.sqlite", work / "ordinary-home/Library/Application Support/Saytile/Saytile.sqlite"]:
        with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as db:
            captured = db.execute("SELECT count(*) FROM recordings WHERE is_recording<>0 OR total_frames<>0").fetchone()[0]
            assert captured == 0, "status menu unexpectedly captured audio"
    print("STATUS_MENU_STORAGE captured_recordings=0")
