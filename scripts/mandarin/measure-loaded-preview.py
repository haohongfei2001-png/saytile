"""Run one isolated native public recording with a fixed external CPU load.

Build preview-cpu-load.c once with cc -O2, then pass that executable to every
arm. Two workers target 1.33 cores and nine target six. Unlike process CPU
seconds, the helper's decode wall time includes waiting for the GPU.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import plistlib
import runpy
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
public_run = runpy.run_path(str(HERE / "measure-preview-cost.py"))["public_run"]
score = runpy.run_path(str(HERE / "score-live-cadence.py"))["measure"]


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def thermal_state():
    # Some systems omit thermal limits. Preserve the actual OS response.
    observed = subprocess.run(["pmset", "-g", "therm"], capture_output=True, text=True)
    return observed.stdout.strip() if observed.returncode == 0 else None


@contextmanager
def fixed_load(helper, count, result):
    workers = []
    observations = []
    failures = []
    before = {"thermal": thermal_state(), "load_average": os.getloadavg()}
    try:
        for _ in range(count):
            workers.append(subprocess.Popen([helper], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
        time.sleep(4)
        if any(p.poll() is not None for p in workers):
            raise RuntimeError("A load worker exited before the native replay")
        yield
    finally:
        for process in workers:
            if process.poll() is None:
                process.terminate()
        for process in workers:
            try:
                output, error = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                output, error = process.communicate()
            if process.returncode == 0:
                item = json.loads(output)
                item["actual_cores"] = round(item["cpu_s"] / item["wall_s"], 5)
                observations.append(item)
            else:
                failures.append({"pid": process.pid, "exit": process.returncode, "detail": error.strip()})
        fractions = [item["actual_cores"] for item in observations]
        achieved = len(fractions) == count and all(0.63 <= core <= 0.70 for core in fractions)
        write_json(result, {
            "workers": observations, "failures": failures, "qos": "userInitiated",
            "period_s": 0.060, "cpu_target_per_period_s": 0.040, "target_cores": count * 2 / 3,
            "observed_cores": round(sum(fractions), 4), "target_met": achieved,
            "helper_sha256": hashlib.sha256(helper.read_bytes()).hexdigest(),
            "before": before, "after": {"thermal": thermal_state(), "load_average": os.getloadavg()},
        })


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    for name in ["app", "manifest", "weights", "audio", "out", "load-helper"]:
        cli.add_argument("--" + name, required=True, type=Path)
    cli.add_argument("--workers", type=int, required=True)
    cli.add_argument("--id", dest="sample_id", required=True)
    cli.add_argument("--sha", required=True)
    args = cli.parse_args()
    if not 1 <= args.workers <= (os.cpu_count() or 1):
        cli.error("--workers must be between one and the number of logical CPUs")
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    if info["SaytileSourceRevision"] != args.sha:
        cli.error("the signed bundle source does not match --sha")
    refs = json.loads(args.manifest.read_text())["samples"]
    selected = [r for r in refs if r["id"] == args.sample_id]
    if len(selected) != 1:
        cli.error("the manifest must contain exactly one matching recording")
    args.out.mkdir(parents=True, exist_ok=False)
    manifest = args.out / "input.json"
    write_json(manifest, {"samples": selected})
    with fixed_load(args.load_helper.resolve(), args.workers, args.out / "load.json"):
        public_run(args.app, manifest, args.sample_id, args.weights, args.audio, args.out / "native")
    write_json(args.out / "cadence.json", score(manifest, args.audio, args.out / "native", args.sha))
    if not json.loads((args.out / "load.json").read_text())["target_met"]:
        print("Load target missed. Measured load, native output and timing are preserved.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
