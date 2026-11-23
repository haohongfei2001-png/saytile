#!/usr/bin/env python3
"""Summarize saved native receipts; never changes the established CER/cadence rules."""
import collections
import gzip
import hashlib
import json
from pathlib import Path
import runpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SCORE = runpy.run_path(str(ROOT / "scripts/score-local-asr.py"))
REVERSALS = runpy.run_path(str(ROOT / "scripts/mandarin/score-preview-reversals.py"))["reversals"]
PRODUCT = "06997bd613ac4dede54450702385259f3bc02f2c"
BASELINE = "8514fea5d45a778aae84854db9b139f7a1fbb85b"


def read(path):
    if not path.exists():
        path = path.with_name(path.name + ".gz")
    raw = path.read_bytes()
    return json.loads(gzip.decompress(raw) if path.suffix == ".gz" else raw)


def receipt(directory, ident):
    return read(directory / ("auto-qwen-small-" + ident + ".json"))


def summarize_normal():
    directory = HERE / "raw/normal15-complete"
    cadence = read(directory / "cadence.json")
    assert cadence["source"] == PRODUCT and cadence["clips"] == 15
    rows = cadence["rows"]
    totals, cpu, peak, reversals, identical = collections.Counter(), 0, 0, [], []
    for row in rows:
        item = receipt(directory, row["id"])
        old = receipt(HERE / "historical15", row["id"])
        assert item["sha"] == PRODUCT and item["exit_code"] == 0
        assert item["audio_sha256"] == old["audio_sha256"] == row["sha256"]
        assert item["providers"] == ["qwen-small"] and item["automatic"]
        identical.append(item["archive"] == old["archive"])
        totals.update(row["final_CER"])
        process = read(directory / row["id"] / "process.json")
        cpu += process["combined_cpu_s"]
        peak = max(peak, process["peak_simultaneous_footprint_MiB"])
        reversals += [{"id": row["id"], **r} for r in REVERSALS(item["publications"], item["endOfFile"])]
    assert all(identical) and (totals["errors"], totals["reference_units"]) == (46, 568)
    return dict(source=PRODUCT, status="PASS", clips=15, accuracy=SCORE["pooled"](totals),
                all_final_texts_equal_to_historical_baseline=all(identical),
                cadence=cadence["summary"], eos_file_s=SCORE["quant"]([r["after_file_s"] for r in rows]),
                cpu_s=round(cpu, 2), peak_combined_footprint_MiB=peak, reversals=reversals)


def pressure_run(name):
    directory = HERE / "raw" / name
    cadence = read(directory / "cadence.json")
    row = cadence["rows"][0]
    item = receipt(directory, "continuous-public-5")
    process = read(directory / "process.json")
    load = read(HERE / "raw" / (name + "-load.json"))
    assert item["audio_sha256"] == row["sha256"] == "5e7b5564803cec7cb90282b0427e99cd345472b758464060bf1f2ae5ba013c04"
    assert item["exit_code"] == 0 and item["providers"] == ["qwen-small"] and item["automatic"]
    assert cadence["source"] == item["sha"] == process["source"]
    return dict(run=name, source=item["sha"], summary=cadence["summary"], row=row,
                process={k: v for k, v in process.items() if k != "samples"},
                load=load, reversals=REVERSALS(item["publications"], item["endOfFile"]))


def main():
    normal = summarize_normal()
    names = sorted(p.parent.name for p in (HERE / "raw").glob("*/cadence.json.gz")
                   if "15" not in p.parent.name)
    runs = {name: pressure_run(name) for name in names}
    definitions = [("repeat-old-1", "repeat-new-1", "AB"),
                   ("repeat-old-2", "repeat-new-2", "BA"),
                   ("closure-old-3", "closure-new-3", "AB")]
    pairs, included = [], set()
    for before, after, order in definitions:
        old, new = runs[before], runs[after]
        assert old["source"] == BASELINE and new["source"] == PRODUCT
        assert old["load"]["target_met"] and new["load"]["target_met"]
        assert old["load"]["helper_sha256"] == new["load"]["helper_sha256"]
        old_item, new_item = (receipt(HERE / "raw" / n, "continuous-public-5") for n in (before, after))
        assert old_item["archive"] == new_item["archive"]
        pairs.append(dict(order=order, old=old, new=new, same_final_text=True))
        included.update((before, after))
    exclusions = []
    for name in names:
        if name in included:
            continue
        reasons = ["load target not met on at least one side of the original paired attempt"]
        if name.startswith("final-"):
            reasons.append("paired old-side overlapped 6.7 seconds of local 440-result scoring; excluded regardless of result")
        exclusions.append(dict(run=name, reasons=reasons, load_target_met=runs[name]["load"]["target_met"]))
    historical = read(HERE / "historical-comparison.json")
    result = dict(
        product_source=PRODUCT, baseline_source=BASELINE,
        normal15=normal, historical15=historical["new"],
        historical_scope="Prior source 9aace8f5b0d7082bd67d2e9b1b6e1db6dcf05883, not a new 563 run. Original raw 15 receipts retained.",
        pressure=dict(status="FAIL", valid_pair_count=len(pairs), pairs=pairs, excluded=exclusions,
                      all_runs=runs, target="same pre-existing <= about 2 s longest useful-word interval; no metric or load threshold changes",
                      conclusion="Three valid pairs completed. 564 maxima 2.370/3.368/2.000 s vs 563 1.987/3.420/1.999 s. No reliable cadence or CPU gain established."),
        retained_failures=[
            "initial normal15 exited at fifth sample without inner diagnostic files; cause UNKNOWN, outer log retained; same sample retry and full15 subsequently passed",
            "insufficient-load pairs retained and excluded by original load assertion, not by recognition outcome",
            "final-old-3 scoring overlap and associated pair retained; one clean replacement AB pair completed after other work stopped"],
        metric_sources={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [
            ROOT / "scripts/score-local-asr.py", ROOT / "scripts/mandarin/score-live-cadence.py",
            ROOT / "scripts/mandarin/score-preview-reversals.py", ROOT / "research/asr-2026-11-06/scripts/score.py"]})
    (HERE / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"normal15": {k:v for k,v in normal.items() if k != "cadence"},
                      "pressure_status": result["pressure"]["status"], "valid_pairs": len(pairs)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
