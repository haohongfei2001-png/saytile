#!/usr/bin/env python3
"""Actual old/new release binaries + real versions through Sparkle's installer.

Only disposable bundle IDs/feed URLs are substituted; neither version/build nor
executable bytes are changed. The native host-app relaunch is a separate test.
"""
import argparse
import functools
import http.server
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


SUPPORT = module("update_release_support", ROOT / "distribution/create-update.py")
STORE = module("update_store_support", ROOT / "scripts/mandarin/check-app-rollback.py")
run, digest = SUPPORT.run, SUPPORT.digest


def info(app):
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())


def app_identity(app):
    meta = info(app)
    return {"source": meta["SaytileSourceRevision"], "version": meta["CFBundleShortVersionString"],
            "build": meta["CFBundleVersion"], "bundle_id": meta["CFBundleIdentifier"],
            "executable_sha256": digest(app / "Contents/MacOS/Saytile"), "info_sha256": digest(app / "Contents/Info.plist")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("old", "candidate", "sparkle", "cli", "probe", "probe-receipt", "output"):
        parser.add_argument("--" + key, required=True, type=Path)
    parser.add_argument("--expected-source", required=True)
    parser.add_argument("--old-source", required=True)
    parser.add_argument("--signing-account", default="app.saytile.updates.v1")
    args = parser.parse_args()
    old, candidate, cli = args.old.resolve(), args.candidate.resolve(), args.cli.resolve()
    old_meta, new_meta = info(old), info(candidate)
    SUPPORT.validate_metadata(old_meta, args.old_source)
    SUPPORT.validate_metadata(new_meta, args.expected_source)
    assert old_meta["CFBundleIdentifier"] == new_meta["CFBundleIdentifier"]
    assert old_meta["SUPublicEDKey"] == new_meta["SUPublicEDKey"]
    old_version = tuple(int(v) for v in old_meta["CFBundleShortVersionString"].split("."))
    new_version = tuple(int(v) for v in new_meta["CFBundleShortVersionString"].split("."))
    assert new_version >= old_version and int(new_meta["CFBundleVersion"]) > int(old_meta["CFBundleVersion"])
    provenance = json.loads(args.probe_receipt.read_text())
    assert provenance["status"] == "PASS" and provenance["source_dirty"] is False
    assert provenance["source_revision"] == args.expected_source and provenance["probe_sha256"] == digest(args.probe)
    assert provenance["fixture_network_denied"] is True and provenance["passed"] == len(provenance["checks"]) >= 16
    original = [app_identity(app) for app in (old, candidate)]
    for app in (old, candidate):
        run("codesign", "--verify", "--deep", "--strict", app)
    identities = re.findall(r'(\b[0-9A-F]{40}) "Developer ID Application:', run("security", "find-identity", "-v", "-p", "codesigning"))
    assert len(identities) == 1
    args.output.mkdir(parents=True, exist_ok=False)
    result = dict(status="FAIL", original_apps=original, current_installation="NOT_ACCESSED", production_data="NOT_ACCESSED",
        real_version_numbers=True, real_release_binary_bytes=True, scope="Sparkle CLI and real installer; host-app shutdown/relaunch tested separately",
        notes_scope="signed inline text parsed by Sparkle; standard user-driver visual acceptance is separate",
        key_scope="existing account; signing tool internal access; no generated or exported key")
    requests = []
    server = None
    fixture_id = "app.saytile.update-fixture." + uuid.uuid4().hex
    cache = Path.home() / "Library/Caches" / fixture_id
    assert not cache.exists()
    root = Path(tempfile.mkdtemp(prefix="saytile-release-update-", dir="/private/tmp"))
    try:
        installed, newer = root / "Applications/Saytile.app", root / "target/Saytile.app"
        data, feed = root / "archive", root / "feed"
        feed.mkdir()

        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                requests.append(dict(path=self.path, at=time.time()))
                if self.path not in ("/appcast.xml", "/update.zip"):
                    self.send_error(404)
                    return
                super().do_GET()

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=feed))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{server.server_port}/"
        for source, destination in ((old, installed), (candidate, newer)):
            destination.parent.mkdir()
            run("ditto", "--norsrc", source, destination)
            metadata = info(destination)
            metadata.update(CFBundleIdentifier=fixture_id, SaytileUpdateBundleIdentifier=fixture_id, SaytileUpdateChannel="fixture",
                            SUFeedURL=url + "appcast.xml", SUEnableAutomaticChecks=False)
            (destination / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
            run("codesign", "--force", "--options", "runtime", "--timestamp=none", "--sign", identities[0], destination)
            run("codesign", "--verify", "--deep", "--strict", destination)
            assert digest(destination / "Contents/MacOS/Saytile") == digest(source / "Contents/MacOS/Saytile")
        STORE.open_fixture(installed, data, 0)
        STORE.seed(data, args.probe.resolve())
        STORE.open_fixture(installed, data, 2)
        before = STORE.snapshot(data, 2)
        paragraphs = STORE.paragraph_state(data)
        canary = data / "LocalModels/test-cache/model-marker"
        canary.parent.mkdir(parents=True)
        canary.write_bytes(b"Existing local model: preserve bytes and modification time during update")
        canary_hash, canary_time = digest(canary), canary.stat().st_mtime_ns
        archive = feed / "update.zip"
        run("ditto", "-c", "-k", "--keepParent", newer, archive)
        archive_hash = digest(archive)
        sign = args.sparkle.resolve() / "bin/sign_update"
        signature = SUPPORT.sign_archive(sign, args.signing_account, archive, old_meta["SUPublicEDKey"])
        notes = "Saytile " + new_meta["CFBundleShortVersionString"] + "\n保留原音、文字、历史修改稿和模型缓存。"
        # Build the same inline-note item as the public artifact, then change only
        # the fixture identity/location before signing this private loopback feed.
        tree = ET.fromstring(SUPPORT.appcast(new_meta, "https://example.invalid/update.zip", archive.stat().st_size, signature, notes))
        tree.find("./channel/item/enclosure").set("url", url + "update.zip")
        tree.find(f"./channel/{{{SUPPORT.SPARKLE}}}bundleIdentifier").text = fixture_id
        appcast = feed / "appcast.xml"
        appcast.write_bytes(ET.tostring(tree, encoding="utf-8", xml_declaration=True))
        run(sign, "--account", args.signing_account, appcast)
        run(sign, "--account", args.signing_account, "--verify", appcast)

        def check(label):
            command = [str(cli), str(installed), "--check-immediately", "--grant-automatic-checks", "--verbose"]
            outcome = subprocess.run(command, capture_output=True, text=True, timeout=180)
            (args.output / (label + ".stdout.log")).write_text(outcome.stdout)
            (args.output / (label + ".stderr.log")).write_text(outcome.stderr)
            return outcome

        def flip():
            with archive.open("r+b") as stream:
                stream.seek(256); value = stream.read(1)[0]; stream.seek(256)
                stream.write(bytes([value ^ 1])); stream.flush(); os.fsync(stream.fileno())

        flip()
        rejected = check("corrupt")
        assert rejected.returncode != 0 and "4005 (SUSparkleErrorDomain)" in rejected.stderr
        assert info(installed)["CFBundleVersion"] == old_meta["CFBundleVersion"]
        assert STORE.snapshot(data, 2) == before
        flip()
        assert digest(archive) == archive_hash
        accepted = check("valid")
        assert accepted.returncode == 0, accepted.stderr
        assert info(installed)["CFBundleVersion"] == new_meta["CFBundleVersion"]
        assert info(installed)["CFBundleShortVersionString"] == new_meta["CFBundleShortVersionString"]
        assert digest(installed / "Contents/MacOS/Saytile") == original[1]["executable_sha256"]
        run("codesign", "--verify", "--deep", "--strict", installed)
        STORE.open_fixture(installed, data, 2)
        assert STORE.snapshot(data, 2) == before and STORE.paragraph_state(data) == paragraphs
        assert digest(canary) == canary_hash and canary.stat().st_mtime_ns == canary_time
        current = check("already-current")
        assert current.returncode == 4 and "no new update" in current.stderr.lower()
        # Reopening the same isolated archive in the old real binary verifies
        # manual rollback compatibility without letting Sparkle downgrade users.
        STORE.open_fixture(old, data, 2)
        assert STORE.snapshot(data, 2) == before and STORE.paragraph_state(data) == paragraphs
        STORE.open_fixture(installed, data, 2)
        assert STORE.snapshot(data, 2) == before
        assert [app_identity(app) for app in (old, candidate)] == original
        result.update(status="PASS", fixture_bundle_id=fixture_id, version_before=old_meta["CFBundleShortVersionString"],
            version_after=new_meta["CFBundleShortVersionString"], build_before=old_meta["CFBundleVersion"], build_after=new_meta["CFBundleVersion"],
            corrupted_archive_rejected=True, valid_archive_installed=True, candidate_signature_verified=True,
            upgraded_app_launched_offline=True, current_version_not_reinstalled=True, manual_rollback_reopened=True,
            original_packages_unchanged=True, fixture_before=before, fixture_after=STORE.snapshot(data, 2),
            paragraph_metadata_preserved=True, model_cache_bytes_and_mtime_preserved=True,
            signing_account=args.signing_account, published_public_key=old_meta["SUPublicEDKey"],
            archive_sha256=archive_hash, appcast_sha256=digest(appcast), probe_sha256=digest(args.probe),
            cli_sha256=digest(cli), signing_tool_sha256=digest(sign))
    except Exception as error:
        result["failure"] = str(error)
        raise
    finally:
        if server:
            server.shutdown()
        (args.output / "requests.json").write_text(json.dumps(requests, indent=2) + "\n")
        result["runner_sha256"] = digest(Path(__file__))
        (args.output / "receipt.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        subprocess.run(["defaults", "delete", fixture_id], capture_output=True)
        if cache.exists():
            shutil.rmtree(cache)
        shutil.rmtree(root)
    print(json.dumps({key: result[key] for key in ("status", "version_before", "version_after", "build_before", "build_after")}, indent=2))


if __name__ == "__main__":
    main()
