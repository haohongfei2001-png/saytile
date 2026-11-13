"""Compare the delivered local default with controls on identical archived clips.

Run from a checkout containing the public Mandarin manifests and quality receipts.
The twenty deterministic noise/volume variants are reported separately.
"""
import argparse
import json
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[2]
paths = runpy.run_path(str(ROOT / "scripts/mandarin/compare-paths.py"))
CONTROLS = [
    ("baseline", "apple", "product"),
    ("baseline", "qwen-small", "product"),
    ("candidate", "apple", "product"),
    ("candidate", "sherpa", "product"),
    ("candidate", "qwen-small", "product"),
    ("candidate", "qwen-large", "product"),
    ("unforced", "qwen-small", "product"),
    ("delivery", "qwen-small", "direct"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipts", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--partial", action="store_true", help="Write a checkpoint with only completed controls")
    args = parser.parse_args()
    fixture = ROOT / "evidence/mandarin"
    manifests = {key: json.loads((fixture / f"{key}.json").read_text()) for key in ("paired", "aishell")}
    originals, variants = [], []
    for manifest in manifests.values():
        for row in manifest:
            (variants if row["source"] in {"quiet", "noise15db"} else originals).append(row)
    assert len(originals) == 420 and len(variants) == 20

    versions = {build: json.loads((args.receipts / build / "metrics.json").read_text())["source"]
                for build, _, _ in CONTROLS}
    ab = json.loads((args.receipts / "language-ab/results.json").read_text())
    versions["unforced"] += " + verified worker " + ab["arms"]["unforced"]["signed_worker_sha256"]
    target = paths["stage"](args.receipts / "delivery", "qwen-small", "product", manifests)
    report = {"source_by_build": versions, "groups": {}}
    for name, rows in [("original420", originals), ("derived20", variants)]:
        outcomes = {}
        for build, model, method in CONTROLS:
            left = paths["stage"](args.receipts / build, model, method, manifests)
            label = f"{build}/{model}/{method} -> delivery/qwen-small/product"
            paired = paths["comparison"](left, target, rows)
            if paired:
                outcomes[label] = paired
            elif not args.partial:
                raise ValueError(f"Incomplete control {label} for {name}")
        report["groups"][name] = outcomes
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    main()
