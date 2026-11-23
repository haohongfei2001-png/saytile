"""Bounded follow-up for the two observed first-output outliers, plus ordinary CPU contention.

This does not replace the original 15-clip results. Every arm is serial and uses
the same signed app and public PCM with unchanged scoring functions.
"""
import argparse
import json
from pathlib import Path
import runpy
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline", "candidate", "manifest", "weights", "audio", "load-helper", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--resume", action="store_true", help="Keep every existing success/failure, execute only absent arms")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    measure = runpy.run_path(str(here / "measure-preview-cost.py"))["public_run"]
    fixed_load = runpy.run_path(str(here / "measure-loaded-preview.py"))["fixed_load"]
    score = runpy.run_path(str(here / "score-live-cadence.py"))["measure"]
    refs = json.loads(args.manifest.read_text())["samples"]
    cases = [(name, False) for name in (
        "ascend-mixed-a0b0e736637c643c", "ascend-mixed-ee4e2d5087648134")]
    cases.append(("continuous-public-5", True))
    rows, failures = [], []
    for sample, loaded in cases:
        for pair in range(3):
            arms = [("qwen-022", args.baseline), ("qwen-preview", args.candidate)]
            if pair % 2:
                arms.reverse()
            for label, app in arms:
                deadline = time.monotonic() + 5
                while subprocess.run(["pgrep", "-x", "SaytileModelWorker"], capture_output=True).returncode == 0 and time.monotonic() < deadline:
                    time.sleep(.1)
                assert subprocess.run(["pgrep", "-x", "SaytileModelWorker"], capture_output=True).returncode == 1
                folder = args.out / sample / str(pair + 1) / label
                if args.resume and folder.exists():
                    if (folder / "cadence.json").exists():
                        receipt = json.loads((folder / "native" / f"qwen-small-{sample}.json").read_text())
                        rows.append(dict(sample=sample, pair=pair + 1, arm=label, loaded=loaded,
                                         source=receipt["sha"], result=str(folder)))
                    else:
                        failures.append(dict(sample=sample, pair=pair + 1, arm=label,
                                             reason="Retained original incomplete/failed arm; not retried", result=str(folder)))
                    continue
                folder.mkdir(parents=True, exist_ok=False)
                manifest = folder / "input.json"
                manifest.write_text(json.dumps(dict(samples=[r for r in refs if r["id"] == sample])))
                kwargs = dict(app=app, manifest=manifest, sample_id=sample, weights=args.weights,
                              audio=args.audio, out=folder / "native", automatic=False)
                try:
                    if loaded:
                        with fixed_load(args.load_helper.resolve(), 2, folder / "load.json"):
                            measure(**kwargs)
                    else:
                        measure(**kwargs)
                except Exception as error:
                    failures.append(dict(sample=sample, pair=pair + 1, arm=label, reason=repr(error), result=str(folder)))
                    (args.out / "failures.json").write_text(json.dumps(failures, indent=2))
                    continue
                receipt = json.loads((folder / "native" / f"qwen-small-{sample}.json").read_text())
                result = score(manifest, args.audio, folder / "native", receipt["sha"], automatic=False)
                (folder / "cadence.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
                rows.append(dict(sample=sample, pair=pair + 1, arm=label, loaded=loaded,
                                 source=receipt["sha"], result=str(folder)))
                (args.out / "progress.json").write_text(json.dumps(rows, indent=2))
    (args.out / "failures.json").write_text(json.dumps(failures, indent=2))
    (args.out / "complete.json").write_text(json.dumps(dict(observations=len(rows), failures=failures), indent=2))
    if failures:
        raise SystemExit("One or more native arms failed; original evidence is retained")


if __name__ == "__main__":
    main()
