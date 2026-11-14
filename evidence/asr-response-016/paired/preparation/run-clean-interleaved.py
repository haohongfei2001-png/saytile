"""Task-local orchestration of existing native harnesses; no product changes."""
import argparse
from collections import Counter
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--candidate", type=Path, required=True)
parser.add_argument("--sha", required=True)
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
repo = Path("/private/tmp/saytile-asr-response")
task = Path("/private/tmp/saytile-response-bench")
research = Path("/private/tmp/saytile-local-quality-20261114/.build")
weights = research / "local-asr/weights"
corpora = [("panels", Path("/private/tmp/saytile-cadence-measure/panels-first-worst.json"), research / "mandarin/wav"),
           ("extended", repo / "evidence/mandarin-quality-20261114/delivery/extended/samples.json", research / "mandarin/bench/final-long-wav")]
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=False)


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def run(command, logfile=None):
    if logfile:
        with logfile.open("w") as log:
            subprocess.run([str(x) for x in command], cwd=repo, stdout=log, stderr=subprocess.STDOUT, check=True)
    else:
        subprocess.run([str(x) for x in command], cwd=repo, check=True)


def environment(label):
    processes = []
    for line in subprocess.check_output(["ps", "-axo", "pid=,ppid=,pcpu=,comm="], text=True).splitlines():
        if any(part in line for part in ("Saytile", "swift-frontend", "swiftc", "clang")):
            processes.append(line.strip())
    state = {"label": label, "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
             "system_uptime": time.monotonic(),
             "load": subprocess.check_output(["sysctl", "-n", "vm.loadavg"], text=True).strip(),
             "processes": processes}
    with (out / "environment.jsonl").open("a") as stream:
        stream.write(json.dumps(state, ensure_ascii=False) + "\n")
    # Do not terminate/reconfigure another app or compete with its recognizer.
    if any("SaytileModelWorker" in line or "SaytileSherpa" in line for line in processes):
        raise RuntimeError("An ASR helper is active before the next fixture; preserve and inspect")
    if any(any(part in line for part in ("swift-frontend", "swiftc", "clang")) for line in processes):
        raise RuntimeError("Compiler is active; clean paired run has not started/resumed")


environment("initial")
candidate = out / "candidate.app"
run(["ditto", args.candidate, candidate])
apps = {"baseline": task / "baseline-484.app", "candidate": candidate}
sources = {"baseline": "ab8545507c79640ec3f419e33467a0263c154844", "candidate": args.sha}
identities = {}
for arm, app in apps.items():
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info["SaytileSourceRevision"] != sources[arm] or info.get("SaytileSourceDirty", False):
        raise RuntimeError("Source identity mismatch or dirty app: " + arm)
    run(["codesign", "--verify", "--deep", "--strict", app], out / (arm + "-codesign.log"))
    identities[arm] = {"app": str(app), "sha": sources[arm], "version": info["CFBundleShortVersionString"],
                       "build": info["CFBundleVersion"], "executable_sha256": digest(app / "Contents/MacOS/Saytile"),
                       "helper_sha256": digest(app / "Contents/Helpers/SaytileModelWorker")}
    (out / arm).mkdir()
(out / "identities.json").write_text(json.dumps(identities, ensure_ascii=False, indent=2) + "\n")
index = 0
for group, manifest, audio in corpora:
    samples = json.loads(manifest.read_text())["samples"]
    for sample in samples:
        single = out / ("fixture-" + sample["id"] + ".json")
        single.write_text(json.dumps({"samples": [sample]}, ensure_ascii=False, indent=2) + "\n")
        order = ["baseline", "candidate"] if index % 2 == 0 else ["candidate", "baseline"]
        for arm in order:
            label = f"{group}/{index + 1}/{sample['id']}/{arm}"
            environment(label)
            print("START", label, datetime.datetime.now(datetime.timezone.utc).isoformat(), flush=True)
            directory = out / arm / group
            run(["python3", repo / "scripts/test-local-panels.py", "--app", apps[arm], "--weights", weights,
                 "--audio", audio, "--paired", single, "--out", directory, "--models", "qwen-small", "--automatic", "--limit", "1"],
                out / (label.replace("/", "-") + ".log"))
            screenshot = directory / "auto-qwen-small-mid-speech.png"
            if screenshot.exists():
                screenshot.rename(directory / (sample["id"] + "-mid-speech.png"))
            print("DONE", label, flush=True)
        index += 1
    for arm in apps:
        arm_root = out / arm
        score = arm_root / (group + ".json")
        run(["python3", repo / "scripts/mandarin/score-live-cadence.py", "--manifest", manifest, "--audio", audio,
             "--receipts", arm_root / group, "--sha", sources[arm], "--out", score])
        run(["python3", repo / "scripts/mandarin/score-stop-response.py", "--cadence", score, "--receipts", arm_root / group,
             "--out", arm_root / ("stop-" + group + ".json")])
        if group == "panels":
            run(["python3", repo / "scripts/mandarin/score-preview-words.py", "--cadence", score, "--manifest", manifest,
                 "--receipts", arm_root / group, "--tokenizer", task / "reference-words", "--out", arm_root / "words-panels.json"])
    run(["python3", repo / "scripts/mandarin/compare-live-cadence.py", "--manifest", manifest,
         "--old", out / "baseline" / group, "--new", out / "candidate" / group,
         "--output", out / ("paired-live-" + group + ".json")]) if group == "panels" else None
run(["python3", repo / "scripts/mandarin/compare-preview-cost.py", "--old", out / "baseline", "--new", out / "candidate",
     "--out", out / "paired-revisions.json"])
for arm in apps:
    run(["python3", repo / "scripts/mandarin/score-preview-reversals.py", out / arm / "panels", out / arm / "extended",
         "--output", out / arm / "reversals.json"])
print("PAIRED_NATIVE_COMPLETE", flush=True)
for index, arm in enumerate(["baseline", "candidate", "baseline", "candidate"], 1):
    environment(f"cpu/{index}/{arm}")
    print("CPU_START", index, arm, flush=True)
    run(["python3", repo / "scripts/mandarin/measure-preview-cost.py", "--app", apps[arm],
         "--manifest", corpora[1][1], "--id", "continuous-public-5", "--weights", weights,
         "--audio", corpora[1][2], "--out", out / "cpu" / (str(index) + "-" + arm)],
        out / ("cpu-" + str(index) + "-" + arm + ".log"))
    print("CPU_DONE", index, arm, flush=True)
environment("complete")
print("CLEAN_INTERLEAVED_COMPLETE", flush=True)
