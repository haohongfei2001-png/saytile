#!/usr/bin/env python3
"""Three predeclared AB / BA / AB native pairs; score only after inference ends.

Uses the existing 38.8 s public recording, load helper, per-process resource
sampler and unchanged cadence/CER scorers. All failed runs are retained.
"""
import argparse
import json
from pathlib import Path
import plistlib
import runpy
import time

ROOT = Path(__file__).resolve().parents[2]
measure = runpy.run_path(str(ROOT / "scripts/mandarin/measure-preview-cost.py"))["public_run"]
load = runpy.run_path(str(ROOT / "scripts/mandarin/measure-loaded-preview.py"))["fixed_load"]
score = runpy.run_path(str(ROOT / "scripts/mandarin/score-live-cadence.py"))["measure"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("before", "after", "weights", "audio", "load-helper", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--quiet-seconds", type=float, default=8)
    args = parser.parse_args()
    if not 8 <= args.quiet_seconds <= 120:
        parser.error("quiet interval must be 8–120 seconds, applied identically before every arm")
    args.out.mkdir(parents=True, exist_ok=False)
    (args.out / "protocol.json").write_text(json.dumps(dict(
        order=[["before", "after"], ["after", "before"], ["before", "after"]],
        quiet_seconds_before_each_arm=args.quiet_seconds, load_and_score_rules="unchanged"), indent=2))
    apps = {"before": args.before, "after": args.after}
    manifest = ROOT / "evidence/mandarin/continuous.json"
    runs = []
    # Fixed order is committed before observing the first result. A failed load
    # remains a failed pair; this script never retries it or selects a better run.
    for pair, order in enumerate((('before', 'after'), ('after', 'before'), ('before', 'after')), 1):
        for arm in order:
            time.sleep(args.quiet_seconds)
            name = f"pair-{pair}-{arm}"
            output = args.out / name
            entry = dict(pair=pair, arm=arm, order=list(order), directory=name)
            try:
                with load(args.load_helper, 8, args.out / f"{name}-load.json"):
                    measure(apps[arm], manifest, "continuous-public-5", args.weights, args.audio, output)
            except Exception as error:
                entry["failure"] = repr(error)
            runs.append(entry)
            (args.out / "runs.json").write_text(json.dumps(runs, indent=2))
            print(name, "FAILED" if "failure" in entry else "saved", flush=True)
    for entry in runs:
        output = args.out / entry["directory"]
        if "failure" not in entry:
            sha = plistlib.loads((apps[entry["arm"]] / "Contents/Info.plist").read_bytes())["SaytileSourceRevision"]
            result = score(manifest, args.audio, output, sha)
            (output / "cadence.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
