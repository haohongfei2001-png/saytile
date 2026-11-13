"""Locate model, segmentation and publication disagreements on the same public PCM.

A direct/product difference identifies the path on which the error changed. It
does not by itself identify VAD, endpointing or publication as the cause.
"""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import runpy
import random

root = Path(__file__).resolve().parents[2]
score = runpy.run_path(str(root / "scripts/score-local-asr.py"))
models = ("apple", "sherpa", "qwen-small", "qwen-large")


def stage(folder, model, path, reference):
    data = {}
    for name, rows in reference.items():
        target = folder / "runs" / f"{name}-{model}-{path}.jsonl"
        if target.is_file():
            results = [json.loads(line) for line in target.read_text().splitlines()]
            assert [r["id"] for r in results] == [r["id"] for r in rows], target
            for result in results:
                assert result["model"] == model and result["path"] == path
                data[result["id"]] = result
    return data


def paired_error_difference(entries):
    # Resample whole clips within each corpus; a repeated character is not an
    # independent observation. This interval only describes this fixed corpus mix.
    strata = defaultdict(list)
    for row in entries:
        strata[row["source"]].append((row["change"], row["reference_units"]))
    rng = random.Random(20261114)
    rates = []
    for _ in range(2000):
        errors = units = 0
        for clips in strata.values():
            for delta, count in rng.choices(clips, k=len(clips)):
                errors += delta
                units += count
        rates.append(100 * errors / units)
    rates.sort()
    return {"difference_pp": round(100 * sum(r["change"] for r in entries) /
                                   sum(r["reference_units"] for r in entries), 3),
            "paired_clip_bootstrap_95_pp": [round(rates[i], 3) for i in (49, 1949)],
            "improved": sum(r["change"] < 0 for r in entries), "regressed": sum(r["change"] > 0 for r in entries)}


def comparison(a, b, expected):
    if not a or not b:
        return None
    entries = []
    changes = Counter()
    for row in expected:
        key = row["id"]
        if key not in a or key not in b:
            return None
        left, right = a[key], b[key]
        anchor = row["reference"]
        first, second = [score["rating"](anchor, item["text"])["errors"] for item in [left, right]]
        diff = second - first
        changes["improved" if diff < 0 else "regressed" if diff > 0 else "unchanged"] += 1
        changes["first_errors"] += first
        changes["second_errors"] += second
        changes["first_empty"] += not left["text"].strip()
        changes["second_empty"] += not right["text"].strip()
        entries.append(dict(id=key, source=row["source"], errors_before=first, errors_after=second,
                            change=diff, reference_units=len(score["norm"](anchor)), before=left["text"], after=right["text"],
                            states_before=left["states"], states_after=right["states"]))
    return {"rows": len(entries), "counts": changes,
            "paired": paired_error_difference(entries),
            "by_source": {s: paired_error_difference([r for r in entries if r["source"] == s])
                          for s in sorted({r["source"] for r in entries})}, "largest_gains": sorted(
        (e for e in entries if e["change"] < 0), key=lambda e: e["change"])[:7],
        "largest_regressions": sorted(
            (e for e in entries if e["change"] > 0), key=lambda e: -e["change"])[:7]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["baseline", "candidate", "out"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    fixture = root / "evidence/mandarin"
    manifests = {key: json.loads((fixture / (key + ".json")).read_text()) for key in ["paired", "aishell"]}
    all_rows = [r for m in manifests.values() for r in m]
    references = [r for r in all_rows if r["source"] not in {"quiet", "noise15db"}]
    assert len(references) == 420 and len(all_rows) == 440
    report = {}
    for model in models:
        before = stage(args.baseline, model, "product", manifests)
        after = stage(args.candidate, model, "product", manifests)
        direct = stage(args.candidate, model, "direct", manifests)
        groups = [
            ("product_old_to_new", before, after),
            ("candidate_direct_to_product", direct, after),
        ]
        report[model] = {name: result for name, left, right in groups
                         if (result := comparison(left, right, references)) is not None}
    report["default_comparisons"] = {}
    for older, earlier_dir, newer in [("apple", args.baseline, "qwen-small"), ("apple", args.baseline, "qwen-large"),
                                      ("qwen-small", args.candidate, "qwen-large")]:
        outcome = comparison(stage(earlier_dir, older, "product", manifests),
                             stage(args.candidate, newer, "product", manifests), references)
        if outcome:
            label = "baseline" if earlier_dir == args.baseline else "candidate"
            report["default_comparisons"][f"{label}_{older}_to_candidate_{newer}"] = outcome
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    main()
