"""Same fixed wall-paced clips, rotating route order, one native process tree at a time."""
import argparse
import json
from pathlib import Path
import runpy
import subprocess

p = argparse.ArgumentParser(description=__doc__)
for name in ["candidate", "baseline", "manifest", "weights", "audio", "out"]:
    p.add_argument("--" + name, type=Path, required=True)
a = p.parse_args()
measure = runpy.run_path(str(Path(__file__).with_name("measure-preview-cost.py")))["public_run"]
routes = [("qwen-022", a.baseline, "qwen-small"),
          ("qwen-preview", a.candidate, "qwen-small"),
          ("nemotron", a.candidate, "nemotron-metal")]
failures = []
for i, row in enumerate(json.loads(a.manifest.read_text())["samples"]):
    order = routes[i % len(routes):] + routes[:i % len(routes)]
    for label, app, model in order:
        for process in ["SaytileModelWorker", "SaytileSherpa", "MandarinCohort"]:
            assert subprocess.run(["pgrep", "-x", process], capture_output=True).returncode == 1, process
        dest = a.out / label / row["id"]
        try:
            measure(app, a.manifest, row["id"], a.weights, a.audio, dest, model=model, automatic=False)
        except Exception as error:
            # public_run saves native logs, raw receipt and resource samples first.
            failures.append(dict(route=label, sample=row["id"], error=repr(error)))
            a.out.mkdir(parents=True, exist_ok=True)
            (a.out / "failures.json").write_text(json.dumps(failures, indent=2))
            print(json.dumps(failures[-1]), flush=True)
(a.out / "completion.json").write_text(json.dumps(dict(clips=i + 1, routes=len(routes), failures=failures), indent=2))
