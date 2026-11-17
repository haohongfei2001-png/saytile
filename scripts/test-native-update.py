#!/usr/bin/env python3
"""Real host-app Sparkle update, with disposable identities and a deterministic user driver.

This is not SparkleCLI or a standard-driver visual acceptance claim. Both copies
run the supplied product binary; only their signed fixture versions/paths differ.
"""
import argparse
import base64
import functools
import hashlib
import http.server
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import threading
import time
import uuid

REPO = Path(__file__).resolve().parents[1]
# Both frozen StoreProcessProbe executables were recorded with their build receipts.
LEGACY_PROBE_SHA = "bd2c057e228cd8f1f2285fe6526a0860a7398f114a6a7b0ee23b93e19fe68f68"
ARCHIVE_PROBE_SHA = "efba4ed52e27d5ea387cb04d39d0fdab3b6af746d72faa11981fbe74f246c335"
ARCHIVE_PROBE_SOURCE = "a57ad69df09ccdc37825415b1f7d01321d7ef64793190ff90a04bdd5bc94448e"


def run(*command, timeout=180):
    result = subprocess.run([str(x) for x in command], capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{Path(command[0]).name} failed ({result.returncode}): {result.stderr[-2000:]}")
    return result.stdout.strip()


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def info(app):
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())


def rows(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line]


def seed_helpers():
    path = REPO / "scripts/mandarin/check-app-rollback.py"
    spec = importlib.util.spec_from_file_location("saytile_update_fixture", path)
    common = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(common)
    return common


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("app", "sparkle", "output"):
        parser.add_argument("--" + key, required=True, type=Path)
    parser.add_argument("--expected-source", required=True)
    parser.add_argument("--probe", type=Path, default=Path("/private/tmp/saytile-011-frozen-process/probe"))
    parser.add_argument("--public-feed", help="Optional signed HTTPS empty feed; no release is published by this test")
    parser.add_argument("--public-key", help="Public Ed25519 key for --public-feed")
    args = parser.parse_args()
    args.app = args.app.resolve()
    args.output = args.output.resolve()
    assert re.fullmatch(r"[0-9a-f]{40}", args.expected_source)
    assert bool(args.public_feed) == bool(args.public_key)
    if args.public_feed:
        from urllib.parse import urlsplit
        address = urlsplit(args.public_feed)
        assert address.scheme == "https" and address.hostname and not address.username and not address.password and not address.query and not address.fragment
        assert len(base64.b64decode(args.public_key, validate=True)) == 32
    source = info(args.app)
    assert source["SaytileSourceRevision"] == args.expected_source
    assert source.get("SaytileSourceDirty") is False
    assert not args.probe.is_symlink()
    probe_sha = digest(args.probe)
    assert probe_sha in {LEGACY_PROBE_SHA, ARCHIVE_PROBE_SHA}
    if probe_sha == ARCHIVE_PROBE_SHA:
        assert digest(REPO / "tests/fixtures/StoreProcessProbe.swift") == ARCHIVE_PROBE_SOURCE
    run("codesign", "--verify", "--deep", "--strict", args.app)
    args.output.mkdir(parents=True, exist_ok=False)
    sign = (args.sparkle.resolve() / "bin/sign_update")
    assert sign.is_file()
    identities = re.findall(r'(\b[0-9A-F]{40}) "Developer ID Application:', run("security", "find-identity", "-v", "-p", "codesigning"))
    assert len(identities) == 1, "Select one existing Developer ID identity; do not create credentials"
    session = uuid.uuid4().hex
    root = Path("/private/tmp/saytile-native-update-" + session)
    root.mkdir(mode=0o700)
    bundle_id = "app.saytile.update-fixture." + session
    preferences = bundle_id + ".preferences"
    cache = Path.home() / "Library/Caches" / bundle_id
    assert not cache.exists(), "Random fixture cache must not pre-exist"
    data = root / "archive"
    events = root / "events.jsonl"
    installed = root / "Applications/Saytile.app"
    newer = root / "target/Saytile.app"
    common = seed_helpers()
    server = None
    processes = []
    request_log = []
    result = dict(status="FAIL", source=args.expected_source, seed_probe_sha256=probe_sha, scope="real Saytile NSApplication and AppUpdateController -> SPUUpdater -> Sparkle installer -> argument-free app relaunch", user_driver="deterministic fixture driver; standard Sparkle window interaction NOT_RUN", fixture_bundle_id=bundle_id, original_app_untouched=True, production_data="NOT_ACCESSED", paid_services="NOT_CALLED")
    original_binary = digest(args.app / "Contents/MacOS/Saytile")

    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            request_log.append(dict(path=self.path, at=time.time()))
            if self.path not in ("/appcast.xml", "/update.zip"):
                self.send_error(404)
                return
            super().do_GET()

    def fixture_snapshot():
        state = common.snapshot(data, 2)
        import sqlite3
        with sqlite3.connect((data / "Saytile.sqlite").as_uri() + "?mode=ro", uri=True) as db:
            tables = ("timeline_paragraphs", "natural_paragraph_schema", "timeline_settings")
            metadata = {name: db.execute("SELECT * FROM " + name + " ORDER BY rowid").fetchall() for name in tables}
        state["paragraph_metadata_sha256"] = hashlib.sha256(json.dumps(metadata, sort_keys=True).encode()).hexdigest()
        return state

    def launch(scenario):
        log = (args.output / (scenario + "-host.log")).open("w")
        command = [str(installed / "Contents/MacOS/Saytile"), "--update-review", "--data-directory", str(data), "--update-review-case", scenario]
        environment = dict(os.environ)
        if scenario == "public-empty":
            environment["SAYTILE_UI_CONTROL_PROBE"] = str(root / "native-ui-control-probe")
        proc = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, cwd=installed / "Contents/Resources", env=environment)
        processes.append((proc, log))
        return proc

    def wait_for(predicate, *, process, allow_relaunch=False, timeout=180):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            current = rows(events)
            failures = [row for row in current if row["event"] == "complete" and row["status"] != "PASS"]
            assert not failures, failures
            if predicate(current):
                return current
            code = process.poll()
            if code is not None:
                # The valid source is expected to quit before Sparkle starts its
                # successor. Any earlier/other exit is a failure, not a 3m wait.
                installing = any(row["event"] == "installing" and row["pid"] == process.pid for row in current)
                if code != 0 or not (allow_relaunch and installing):
                    raise RuntimeError(f"Fixture host PID {process.pid} exited {code} before its required native receipt")
            time.sleep(0.25)
        raise TimeoutError("Native host-app update did not produce its required receipt")

    try:
        # Existing migration fixtures: two edited/pinned records, four versions,
        # unfinished drafts, two deterministic WAVs, and unknown dispatch safety.
        common.open_fixture(args.app, data, 0)
        common.seed(data, args.probe)
        common.open_fixture(args.app, data, 2)
        before = fixture_snapshot()
        canary = data / "LocalModels/fixture-version/synthetic-model-marker"
        canary.parent.mkdir(parents=True)
        canary.write_bytes(b"Saytile native update cache continuity; no actual model loaded")
        canary_stamp = canary.stat().st_mtime_ns
        canary_hash = digest(canary)
        feed = root / "feed"
        feed.mkdir()
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=feed))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{server.server_port}/"
        key = root / "session-key"
        key.touch(mode=0o600)
        public_key = run("swift", "-e", 'import Foundation; import CryptoKit; let key = Curve25519.Signing.PrivateKey(); try key.rawRepresentation.base64EncodedData().write(to: URL(fileURLWithPath:CommandLine.arguments[1])); print(key.publicKey.rawRepresentation.base64EncodedString())', key)
        for version, app in ((1, installed), (2, newer)):
            app.parent.mkdir()
            run("ditto", "--norsrc", args.app, app)
            metadata = info(app)
            metadata.update(CFBundleIdentifier=bundle_id, CFBundleVersion=str(version), CFBundleShortVersionString="0.18",
                SUFeedURL=url + "appcast.xml", SUPublicEDKey=public_key, SURequireSignedFeed=True,
                SUSignedFeedFailureExpirationInterval=0,
                SUVerifyUpdateBeforeExtraction=True, SUEnableAutomaticChecks=False, SUAllowsAutomaticUpdates=False,
                SUSendProfileInfo=False, SaytileUpdateBundleIdentifier=bundle_id, SaytileUpdateChannel="fixture",
                SaytileUpdateReview=dict(root=str(root), dataDirectory=str(data), preferencesSuite=preferences,
                    eventLog=str(events), expectedSource=args.expected_source, phase="check" if version == 1 else "relaunch", sessionID=session))
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
            run("codesign", "--force", "--options", "runtime", "--timestamp=none", "--sign", identities[0], app)
            run("codesign", "--verify", "--deep", "--strict", app)
        archive = feed / "update.zip"
        run("ditto", "-c", "-k", "--keepParent", newer, archive)
        archive_hash = digest(archive)
        signature = run(sign, "-f", key, "-p", archive)
        appcast = feed / "appcast.xml"
        appcast.write_text(f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Disposable native update fixture</title><item><title>2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.18</sparkle:shortVersionString><enclosure url="{url}update.zip" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>''')
        run(sign, "-f", key, appcast)

        def flip_archive():
            with archive.open("r+b") as stream:
                stream.seek(256)
                value = stream.read(1)[0]
                stream.seek(256)
                stream.write(bytes([value ^ 1]))
                stream.flush()
                os.fsync(stream.fileno())

        # Deliberate corrupt case: same advertised length/signature, one bad byte.
        flip_archive()
        bad = launch("corrupt")
        wait_for(lambda entries: any(row["event"] == "complete" and row["case"] == "corrupt" for row in entries), process=bad)
        assert bad.wait(timeout=30) == 0
        assert info(installed)["CFBundleVersion"] == "1"
        assert fixture_snapshot() == before
        corrupt_events = [row for row in rows(events) if row["case"] == "corrupt"]
        assert any(row["event"] == "update_error" and any(e["domain"] == "SUSparkleErrorDomain" and e["code"] == 4005 for e in row["errors"]) for row in corrupt_events)
        assert not any(row["event"] in ("ready_to_install", "installing") for row in corrupt_events)
        result["corrupt_archive"] = dict(status="PASS", installed_version="1", archive_unchanged=True, rejection="SUSparkleErrorDomain/4005")

        # A separate, explicit valid case; no automatic retry of the failed check.
        flip_archive()
        assert digest(archive) == archive_hash
        good = launch("valid")
        completed = wait_for(lambda entries: any(row["event"] == "complete" and row["phase"] == "relaunch" for row in entries), process=good, allow_relaunch=True)
        assert good.wait(timeout=30) == 0
        valid = [row for row in completed if row["case"] == "valid"]
        before_launch = [row for row in valid if row["event"] == "launched" and row["phase"] == "check"]
        after_launch = [row for row in valid if row["event"] == "launched" and row["phase"] == "relaunch"]
        assert len(before_launch) == len(after_launch) == 1
        assert before_launch[0]["pid"] != after_launch[0]["pid"]
        assert after_launch[0]["build"] == "2" and after_launch[0]["explicit_data_argument"] is False
        assert after_launch[0]["source"] == args.expected_source
        for required in ("app_check_action", "checking", "update_found", "download_started", "extracting", "ready_to_install", "installing", "archive_loaded", "no_update"):
            assert any(row["event"] == required for row in valid), required
        assert all(row["user_initiated"] for row in valid if row["event"] == "update_found")
        # Target's completion precedes its normal asynchronous shutdown; wait for
        # the exact recorded target PID rather than killing or forcing its save.
        target_pid = after_launch[0]["pid"]
        end = time.monotonic() + 30
        while time.monotonic() < end:
            try:
                os.kill(target_pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
        else:
            raise TimeoutError("Relaunched fixture did not finish normal termination")
        assert info(installed)["CFBundleVersion"] == "2"
        run("codesign", "--verify", "--deep", "--strict", installed)
        assert digest(installed / "Contents/MacOS/Saytile") == digest(newer / "Contents/MacOS/Saytile")
        after = fixture_snapshot()
        assert after == before
        assert canary.stat().st_mtime_ns == canary_stamp and digest(canary) == canary_hash
        assert digest(args.app / "Contents/MacOS/Saytile") == original_binary
        result.update(status="PASS", fixture_before=before, fixture_after=after,
            real_native_install_relaunch=True, version_before="1", version_after="2",
            source_pid=before_launch[0]["pid"], relaunched_pid=target_pid,
            argument_free_relaunch_isolated=True, preference_canary_preserved=True,
            installed_signature_verified=True, model_marker_bytes_and_mtime_unchanged=True,
            update_archive_sha256=archive_hash, update_appcast_sha256=digest(appcast),
            updater_binary_sha256=original_binary, key_scope="ephemeral Ed25519 file; deleted, never emitted or read from Keychain")
        if args.public_feed:
            # Reuse the established native AX harness. It only observes this
            # fixture's PID/window/identifier and never activates or posts keys.
            helper_source = REPO / "Tests/fixtures/NativeUIControlProbe.swift"
            run("swiftc", "-swift-version", "6", "-parse-as-library", helper_source, "-o", root / "native-ui-control-probe")
            result["native_control_helper_source_sha256"] = digest(helper_source)
            # A final re-signed disposable fixture invokes the identical host
            # controller against the real signed empty channel. It installs nothing.
            metadata = info(installed)
            metadata["SUFeedURL"] = args.public_feed
            metadata["SUPublicEDKey"] = args.public_key
            metadata["SaytileUpdateReview"]["phase"] = "public-empty"
            (installed / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
            run("codesign", "--force", "--options", "runtime", "--timestamp=none", "--sign", identities[0], installed)
            run("codesign", "--verify", "--deep", "--strict", installed)
            public = launch("public-empty")
            wait_for(lambda entries: any(row["event"] == "complete" and row["phase"] == "public-empty" for row in entries), process=public)
            assert public.wait(timeout=30) == 0
            public_events = [row for row in rows(events) if row["phase"] == "public-empty"]
            assert any(row["event"] == "no_update" for row in public_events)
            assert any(row["event"] == "settings_control" and row["pressed"] is True and row["candidate_activated"] is False for row in public_events)
            assert not any(row["event"] in ("update_found", "download_started", "ready_to_install") for row in public_events)
            assert fixture_snapshot() == before and digest(canary) == canary_hash and canary.stat().st_mtime_ns == canary_stamp
            screenshot = root / "native-settings-about.png"
            assert screenshot.is_file()
            result["public_empty_feed"] = dict(status="PASS", url=args.public_feed, signature_required=True, no_archive_downloaded=True, no_update_installed=True,
                native_settings_action="AXUIElementPerformAction/AXPress on existing SettingsView", settings_screenshot_sha256=digest(screenshot))
    except Exception as error:
        result["status"] = "FAIL"
        result["failure"] = str(error)
        raise
    finally:
        if server:
            server.shutdown()
        # Only processes created by this test; ordinary app instances are never searched.
        for proc, log in processes:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    proc.kill(); proc.wait(timeout=5)
            log.close()
        # The successor is launched by Sparkle, not Popen. On failure, only act on
        # its recorded PID while its live command still identifies our exact path.
        for row in rows(events):
            if row.get("event") != "launched" or row.get("phase") != "relaunch":
                continue
            pid = row["pid"]
            command = subprocess.run(["ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True).stdout.strip()
            expected = str(installed / "Contents/MacOS/Saytile")
            if command == expected or command.startswith(expected + " "):
                os.kill(pid, 15)
                limit = time.monotonic() + 15
                while time.monotonic() < limit:
                    try:
                        os.kill(pid, 0)
                    except ProcessLookupError:
                        break
                    time.sleep(0.1)
                else:
                    # A stuck successor is evidence to retain, not a reason to
                    # delete files underneath a process or force its data flush.
                    result["cleanup_retained_root"] = str(root)
        if events.exists():
            shutil.copy2(events, args.output / "events.jsonl")
        screenshot = root / "native-settings-about.png"
        if screenshot.is_file():
            shutil.copy2(screenshot, args.output / screenshot.name)
        (args.output / "loopback-requests.json").write_text(json.dumps(request_log, indent=2) + "\n")
        result["runner_sha256"] = digest(Path(__file__))
        result["seed_probe_sha256"] = probe_sha
        (args.output / "receipt.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        for domain in (bundle_id, preferences):
            subprocess.run(["defaults", "delete", domain], capture_output=True)
        if cache.exists():
            shutil.rmtree(cache)
        if result.get("cleanup_retained_root"):
            (root / "session-key").unlink(missing_ok=True)
        else:
            shutil.rmtree(root)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
