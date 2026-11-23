"""Re-score the historical worst Qwen path losses against the same later public recordings.

Example: python3 scripts/mandarin/inspect-finalization-loss.py > /tmp/losses.json
This result concerns a post-hoc subset of accelerated replays; use the full cohort
and independently chosen native panel cohort for product-level comparisons.
"""
import argparse
import json
from pathlib import Path
import runpy

root = Path(__file__).resolve().parents[2]
score = runpy.run_path(str(root / "scripts/score-local-asr.py"))
evidence = root / "evidence/mandarin-quality-20261114"
history = root / "evidence/mandarin/delivery"


def records(files):
    indexed = {}
    for file in files:
        for line in file.read_text().splitlines():
            row = json.loads(line)
            assert row["id"] not in indexed, (file, row["id"])
            indexed[row["id"]] = row
    return indexed


def measured(row, ref, method):
    assert row["model"] == "qwen-small" and row["path"] == method
    return dict(text=row["text"], score=score["rating"](ref, row["text"]),
                states=row["states"], errors=row["errors"], providers=row["providers"])


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--candidate", type=Path, nargs="+", default=[
        evidence / "candidate/runs/paired-qwen-small-product.jsonl"])
    cli.add_argument("--baseline", type=Path, nargs="+", default=None)
    args = cli.parse_args()
    paths = {m: records([history / f"runs/paired-qwen-small-{m}.jsonl"])
             for m in ["direct", "product"]}
    final = records(args.candidate)
    if args.baseline is None:
        base = evidence / "baseline/runs/paired-qwen-small-product.jsonl"
        args.baseline = [base] if base.exists() else []
    earlier = records(args.baseline)
    auto = records([evidence / "unforced/runs/paired-qwen-small-product.jsonl"])
    segmentation = records([evidence / "segmentation-frames.jsonl"])
    replay = json.loads((evidence / "historical-qwen-vad.json").read_bytes())
    refs = json.loads((root / "evidence/mandarin/paired.json").read_bytes())
    fleurs = [r for r in refs if r["source"] == "fleurs"]
    differences = []
    for r in fleurs:
        key = r["id"]
        left, right = [score["rating"](r["reference"], paths[m][key]["text"])
                       for m in ["direct", "product"]]
        differences.append((right["errors"] - left["errors"], key, r))
    assert len(differences) == 160
    cases = []
    for difference, key, r in sorted(differences, reverse=True)[:7]:
        old_direct, old_product = [measured(paths[m][key], r["reference"], m)
                                   for m in ["direct", "product"]]
        new = measured(final[key], r["reference"], "product")
        auto_result = measured(auto[key], r["reference"], "product")
        seg = segmentation[key]
        assert seg["wav_sha256"] == r["audio_sha256"] == replay[key]["wav_sha256"]
        old_seg = replay[key]["segments"]
        assert len(old_seg) == len(old_product["states"])
        cases.append(dict(id=key, duration=r["duration"], wav_sha256=seg["wav_sha256"],
                          reference=r["reference"], historical=old_product,
                          historical_direct=old_direct, historical_product_additional_errors=difference,
                          historical_segments=old_seg, baseline_segments=seg["baseline"],
                          candidate_segments=seg["candidate"], candidate=new, candidate_auto=auto_result,
                          baseline=measured(earlier[key], r["reference"], "product") if earlier else None))
    totals = {name: sum(x[name]["score"]["errors"] for x in cases) for name in
              ["historical_direct", "historical", "candidate", "candidate_auto"] + (["baseline"] if earlier else [])}
    output = dict(scope="Top seven historical ABSOLUTE increases in Qwen CER errors on the original 160 FLEURS clips, ranked before considering subsequent outputs. All recordings are public. These are accelerated fixture observations.",
                  historical_source=json.loads((history / "comparison.json").read_bytes())["app_source"],
                  candidate_inference_source="d2da53545fc51e65c5f893cfb9dec92000e0f873",
                  auto_runtime=json.loads((evidence / "bench-identity.json").read_bytes())["unforced_comparison"],
                  baseline_inference_source="a4f9f08656d1a22d2e0b6c59ad60e36452881010" if earlier else None,
                  note="Per-record errors are compacted in reverse-record order, not aligned to the chronological 'states' array. Each VAD replay measured independently on original PCM; no historical per-frame recognizer traces available.",
                  historical_excess_errors_all_original_fleurs=sum(d[0] for d in differences),
                  historical_excess_errors_in_seven=sum(x["historical_product_additional_errors"] for x in cases),
                  seven_reference_units=sum(x["candidate"]["score"]["reference_units"] for x in cases),
                  seven_errors=totals, cases=cases)
    print(json.dumps(output, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
