"""Alternating signed bundles on fixed clips, one at a time, with no competing Saytile inference."""

import argparse, json, pathlib, subprocess, tempfile, sys

P = pathlib.Path
p = argparse.ArgumentParser()
for key in ["candidate", "baseline", "weights", "wav", "panel_cohort", "out"]:
    p.add_argument("--" + key, type=P, required=True)
a = p.parse_args()
pairs = json.loads(a.panel_cohort.read_text())["samples"]
with tempfile.TemporaryDirectory(prefix="saytile-mandarin-ab-") as tmp:
    for i, row in enumerate(pairs):
        single = P(tmp) / "one.json"
        single.write_text(json.dumps({"samples": [row]}))
        variants = [("current", a.candidate), ("prior", a.baseline)]
        if i % 2:
            variants.reverse()
        for label, app in variants:
            for name in [
                "SaytileSherpa",
                "SaytileModelWorker",
                "MandarinCohort",
                "Cohort",
            ]:
                if (
                    subprocess.run(
                        ["pgrep", "-x", name], capture_output=True
                    ).returncode
                    == 0
                ):
                    raise RuntimeError("concurrent inference " + name)
            dest = a.out / label
            subprocess.run(
                [
                    sys.executable,
                    "scripts/test-local-panels.py",
                    "--app",
                    app,
                    "--weights",
                    a.weights,
                    "--audio",
                    a.wav,
                    "--paired",
                    single,
                    "--out",
                    dest,
                    "--models",
                    "qwen-small",
                    "--limit",
                    "1",
                ],
                check=True,
            )
