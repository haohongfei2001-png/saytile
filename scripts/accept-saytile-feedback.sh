#!/bin/bash
# macOS native single-report probe, independent of the personal App, Keychain and media.
# self-test (offline) | prepare /private/tmp/saytile-feedback-<run> (offline)
# After the shared service is deployed: submit <same-path> once, then status <same-path>.
# Only submit permits POST. A lost response must be reconciled with status and the exact ID.
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
case "${1:-}" in
  self-test) [[ $# == 1 ]] ;;
  prepare|submit|status) [[ $# == 2 ]] ;;
  *) echo 'Usage: accept-saytile-feedback.sh self-test | {prepare|submit|status} /private/tmp/saytile-feedback-<run>' >&2; exit 64 ;;
esac

build="$(mktemp -d /private/tmp/saytile-feedback-probe.XXXXXX)"
trap 'rm -rf "$build"' EXIT
swiftc -module-cache-path "$build/modules" -swift-version 6 -emit-module -emit-module-path "$build/RiftletFeedback.swiftmodule" \
  -emit-library -static -module-name RiftletFeedback -I Sources/CSQLite \
  Sources/RiftletFeedback/*.swift -o "$build/libRiftletFeedback.a"
swiftc -module-cache-path "$build/modules" -swift-version 6 -parse-as-library -I Sources/CSQLite -I "$build" -L "$build" -lRiftletFeedback \
  Sources/SaytileApp/FeedbackSettingsModel.swift tests/fixtures/AcceptSaytileFeedback.swift -o "$build/probe"
version="$(cat packaging/VERSION)"
if [[ "$1" != self-test ]]; then
  "$build/probe" "$1" "$2" "$version"
  exit
fi

# Separate processes exercise durable identity on restart, including a lost POST response.
python3 - "$build" "$version" <<'PY'
import json
import pathlib
import shutil
import subprocess
import sys
import uuid

work = pathlib.Path(sys.argv[1])
def run(action, directory, expected=0):
    result = subprocess.run([work / "probe", action, directory, sys.argv[2]], capture_output=True, text=True)
    if result.returncode != expected:
        raise RuntimeError(f"{action} exit={result.returncode}: {result.stderr} {result.stdout}")
    return json.loads(result.stdout)

# Exercise the publicly documented prepare code path (it uses only the local outbox).
# The /tmp and /private/tmp spellings on Darwin must open the same persisted report.
live_name = "saytile-feedback-selftest-" + str(uuid.uuid4())
live_directory = pathlib.Path("/private/tmp") / live_name
alias = pathlib.Path("/tmp") / live_name
link = pathlib.Path("/private/tmp") / (live_name + "-link")
def expect_refused(action, path):
    result = subprocess.run([work / "probe", action, path, sys.argv[2]], capture_output=True)
    assert result.returncode == 1, (action, path, result.returncode)

assert not live_directory.exists() and not link.exists()
try:
    prepared = run("prepare", live_directory)
    resumed = run("prepare", alias)
    assert not prepared["offline"] and prepared == resumed and prepared["attempts"] == 0
    expect_refused("status", alias)  # No POST, so this must refuse before any GET.
    assert run("prepare", live_directory) == prepared
    link.symlink_to(live_directory, target_is_directory=True)
    expect_refused("prepare", link)
    expect_refused("prepare", work / live_name)
    expect_refused("prepare", str(alias) + "/../" + live_name)
finally:
    link.unlink(missing_ok=True)
    if live_directory.is_dir():
        shutil.rmtree(live_directory)

for lose_reply in (False, True):
    directory = work / ("lost-reply" if lose_reply else "normal")
    prepared = run("offline-prepare", directory)
    receipt = run("offline-lose" if lose_reply else "offline-submit", directory, 2 if lose_reply else 0)
    blocked = run("offline-submit", directory, 2)
    delivered = run("offline-status", directory)
    assert prepared["id"] == receipt["id"] == blocked["id"] == delivered["id"]
    assert prepared["payloadSHA256"] == receipt["payloadSHA256"] == delivered["payloadSHA256"]
    assert prepared["attempts"] == 0 and receipt["attempts"] == blocked["attempts"] == delivered["attempts"] == 1
    assert receipt["result"] == ("unknown" if lose_reply else "received")
    assert blocked["result"] == "already-attempted" and delivered["result"] == "delivered"
    assert run("offline-prepare", directory)["id"] == prepared["id"]
    # A partially lost outbox cannot mint a replacement UUID on re-prepare.
    (directory / "outbox").rename(directory / "missing-outbox")
    refused = subprocess.run([work / "probe", "offline-prepare", directory, sys.argv[2]], capture_output=True)
    assert refused.returncode == 1 and not (directory / "outbox").exists()
print('PASS offline: production prepare via both macOS /tmp aliases, unsafe paths and premature status refused, frozen Saytile wire payload, single POST intent, read-only status, restart and lost-reply identity; no live HTTPS or private Issue.')
PY
