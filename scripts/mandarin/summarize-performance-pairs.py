#!/usr/bin/env python3
"""Summarize every saved pair, including invalid load and failed native runs.

Does not change any CER, reference matching, reversal or load validity rule.
"""
import argparse
import gzip
import json
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[2]
reversals = runpy.run_path(str(ROOT / "scripts/mandarin/score-preview-reversals.py"))["reversals"]


def read(path):
    if not path.exists():
        path = path.with_name(path.name + ".gz")
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == ".gz" else data)


def summarize(directories):
    pairs = []
    for root in directories:
        for before in sorted(root.glob("pair-*-before")):
            number = int(before.name.split('-')[1])
            pair = dict(directory=str(root), pair=number, arms={})
            archives = []
            for arm in ("before", "after"):
                directory = root / f"pair-{number}-{arm}"
                try:
                    raw = read(directory / "auto-qwen-small-continuous-public-5.json")
                    cadence = read(directory / "cadence.json")["rows"][0]
                    process = read(directory / "process.json")
                    load = read(root / (directory.name + "-load.json"))
                    assert raw["sha"] == process["source"]
                    assert raw["audio_sha256"] == cadence["sha256"] == "5e7b5564803cec7cb90282b0427e99cd345472b758464060bf1f2ae5ba013c04"
                    assert raw["recordStates"] == ["completed", "completed"] and raw["providers"] == ["qwen-small"]
                    archives.append(raw["archive"])
                    pair["arms"][arm] = dict(source=raw["sha"], load_valid=load["target_met"],
                        load_cores=load["observed_cores"], first_visible_s=cadence["display"]["first_s"],
                        longest_visible_gap_s=cadence["display"]["longest_s"],
                        fresh_gap_p95_s=cadence["display"]["gap_s"]["p95"],
                        decode=cadence["decode"], eos_s=cadence["after_file_s"],
                        CER=cadence["final_CER"], cpu_s=process["combined_cpu_s"],
                        app_cpu_s=process["app_cpu_s"], worker_cpu_s=process["workers_cpu_s"],
                        observed_peak_MiB=process["peak_simultaneous_footprint_MiB"],
                        reversals=reversals(raw["publications"], raw["endOfFile"]))
                except Exception as error:
                    pair["arms"][arm] = dict(failure=repr(error), load_valid=False)
            pair["valid"] = all(a["load_valid"] for a in pair["arms"].values())
            pair["same_final_text"] = len(archives) == 2 and archives[0] == archives[1]
            pairs.append(pair)
    return dict(valid_pairs=sum(p["valid"] for p in pairs), all_pairs=pairs,
                interpretation="Invalid runs are retained, never counted as valid benefit. No automatic release decision.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", nargs="+", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    args.out.write_text(json.dumps(summarize(args.directories), ensure_ascii=False, indent=2) + "\n")
