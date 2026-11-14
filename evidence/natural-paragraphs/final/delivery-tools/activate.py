# Prepared only: no installation has been executed. Bare SHA is not an activation command.
import ctypes
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = Path("/private/tmp/saytile-natural-paragraphs")
BRANCH = "refs/heads/codex/natural-paragraphs"
BASE = "7fd9296d8eb2bd81379bbaa7287844d0d46703d5"
FIRST_ACCEPTABLE = "7fd9296d8eb2bd81379bbaa7287844d0d46703d5"
APP = Path("/Users/hhf/Applications/Saytile 中文识别候选.app")
PRIOR = Path("/Users/hhf/Documents/GitHub/saytile/dist/panel-boundary-0.14-478")
IMAGE = "Saytile-0.15-mandarin-arm64.dmg"
PRIOR_IMAGE = "Saytile-0.14-mandarin-arm64.dmg"
CONTROL = Path("/private/tmp/saytile-cadence-update")
CONTROL_SHA = "860e7019d983f13c5eeb9b0aa39e5082ac8a41efff3358333838cffe6bd38ac7"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout.strip()


def info(path):
    require(path.is_dir() and not path.is_symlink(), f"Invalid application path: {path}")
    run("codesign", "--verify", "--deep", "--strict", path)
    sig = subprocess.run(["codesign", "-dv", "--verbose=4", path],
                         check=True, text=True, capture_output=True).stderr
    ent = subprocess.run(["codesign", "-d", "--entitlements", ":-", path],
                         check=True, capture_output=True).stdout
    meta = plistlib.loads((path / "Contents/Info.plist").read_bytes())
    return dict(team=re.search(r"^TeamIdentifier=(\w+)$", sig, re.M)[1],
                id=meta["CFBundleIdentifier"], build=meta["CFBundleVersion"],
                version=meta["CFBundleShortVersionString"], source=meta["SaytileSourceRevision"],
                dirty=meta["SaytileSourceDirty"], exe=sha(path / "Contents/MacOS/Saytile"),
                worker=sha(path / "Contents/Helpers/SaytileModelWorker"),
                ent=hashlib.sha256(ent).hexdigest())


def verify_source(chosen):
    require(re.fullmatch("[0-9a-f]{40}", chosen), "Supply the complete candidate source SHA")
    git = ("git", "-C", str(REPO))
    require(run(*git, "remote", "get-url", "origin") ==
            "https://github.com/haohongfei2001-png/saytile.git", "Unexpected source repository")
    require(run(*git, "symbolic-ref", "HEAD") == BRANCH, "Unexpected candidate branch")
    require(run(*git, "rev-parse", "--verify", chosen + "^{commit}") == chosen, "Unknown source")
    run(*git, "merge-base", "--is-ancestor", FIRST_ACCEPTABLE, chosen)
    run(*git, "merge-base", "--is-ancestor", chosen, BRANCH)
    require(run(*git, "show", chosen + ":packaging/VERSION") == "0.15", "Wrong candidate version")


def preflight(chosen):
    verify_source(chosen)
    pkg = Path("/private/tmp/saytile-natural-paragraphs-release-" + chosen[:8])
    require(pkg.is_dir() and not pkg.is_symlink(), "Missing build directory")
    src = pkg / "installed" / APP.name
    require(src.resolve() == src, "Unexpected staged bundle path")
    record = json.loads((pkg / "package.json").read_bytes())
    prior = json.loads((PRIOR / "package.json").read_bytes())
    old, new, prod = info(APP), info(src), info(APP.with_name("Saytile.app"))
    require(old["source"] == prior["source"] == BASE and chosen == new["source"] == record["source"],
            "Installed or selected bundle source changed")
    for observed, expected in [(old, prior), (new, record)]:
        require(observed["id"] == expected["bundle"] == "app.saytile.mac.mandarin-candidate"
                and observed["team"] == "ZB9D4T66QB" and observed["dirty"] is False
                and observed["version"] == expected["version"]
                and observed["build"] == expected["build"]
                and observed["exe"] == expected["app_executable_sha256"]
                and observed["worker"] == expected["worker_sha256"], "Signed bundle differs from verified build")
    require(old["version"] == "0.14" and old["build"] == "478" and new["version"] == "0.15"
            and int(new["build"]) > 478
            and old["worker"] == new["worker"] == "9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e", "Unexpected runtime or version change")
    require(prod["id"] == "app.saytile.mac" and old["ent"] == new["ent"], "Production/candidate identity mismatch")
    rollback = json.loads((pkg / "rollback.json").read_bytes())
    require(rollback["status"] == "PASS" and len(rollback["identities"]) == 2 and rollback.get("natural_paragraph_sidecar") == "PASS", "Missing upgrade/rollback result")
    for observed, tested in zip((old, new), rollback["identities"]):
        require((observed["id"], observed["source"], observed["exe"], observed["build"]) ==
                (tested["bundle_id"], tested["source"], tested["executable_sha256"], tested["build"]),
                "Rollback did not exercise this pair of binaries")
    for folder, receipt, name in [(pkg, record, IMAGE), (PRIOR, prior, PRIOR_IMAGE)]:
        dmg = folder / name
        require(dmg.is_file() and not dmg.is_symlink()
                and sha(dmg) == receipt["dmg_sha256"] and dmg.stat().st_size == receipt["dmg_bytes"],
                "Image digest mismatch")
        run("codesign", "--verify", "--strict", dmg)
    require(not CONTROL.is_symlink() and sha(CONTROL) == CONTROL_SHA, "Unexpected process control helper")
    return src, old, new, prod, prior, record


def stopped_instances(output):
    captured = re.fullmatch(r"old_instances=([0-9]+) graceful=true", output)
    require(captured is not None, "Unrecognized graceful shutdown receipt")
    return int(captured[1])


def exchange(candidate, installed):
    swap = ctypes.CDLL(None, use_errno=True).renamex_np
    swap.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    swap.restype = ctypes.c_int
    if swap(os.fsencode(candidate), os.fsencode(installed), 2):
        raise OSError(ctypes.get_errno(), "Atomic bundle exchange failed")


def restore_previous_if_running(active_before):
    if active_before:
        run("/usr/bin/open", "-g", APP)
        run(CONTROL, "verify")


def activate(chosen):
    src, old, new, prod, prior, record = preflight(chosen)
    production = APP.with_name("Saytile.app")
    stage = Path(tempfile.mkdtemp(prefix=".saytile-update-", dir=APP.parent))
    other = stage / APP.name
    safe_to_clean = True
    try:
        run("ditto", src, other)
        require(info(other) == new, "Staged copy differs")
        stopped = run(CONTROL, "stop")
        active_before = stopped_instances(stopped)
        safe_to_clean = False
        try:
            exchange(other, APP)
        except OSError:
            require(info(APP) == old and info(production) == prod, "Prior bundle cannot be identified after failed swap")
            restore_previous_if_running(active_before)
            safe_to_clean = info(other) == new
            raise
        try:
            require(info(APP) == new and info(other) == old and info(production) == prod, "Exchange verification failed")
            run("/usr/bin/open", "-g", APP)
            active = run(CONTROL, "verify")
        except BaseException:
            run(CONTROL, "stop")
            exchange(other, APP)
            require(info(APP) == old and info(production) == prod, "Rollback verification failed")
            restore_previous_if_running(active_before)
            safe_to_clean = True
            raise
        safe_to_clean = True
        print(json.dumps(dict(status="PASS", old=old, installed=new, production_unchanged=prod,
                              running=active, old_exit=stopped, atomic_swap=True,
                              old_image_sha256=prior["dmg_sha256"], new_image_sha256=record["dmg_sha256"],
                              private_archive_or_keychain_read=False), indent=2))
    finally:
        if safe_to_clean:
            shutil.rmtree(stage)
        else:
            print("Retained staged bundle for recovery: " + str(stage), file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--preflight":
        _, _, new, _, _, _ = preflight(sys.argv[2])
        print(json.dumps(dict(status="PASS", scope="read-only preflight", signed_candidate=new)))
    elif len(sys.argv) == 3 and sys.argv[1] == "--activate":
        activate(sys.argv[2])
    else:
        raise SystemExit("Usage: activate.py --preflight FULL_SHA (read-only) | --activate FULL_SHA (explicit later installation)")
