"""Compare the unchanged CER scorer on full recordings and the actual laid-out text.

Invoke with the labeled public manifests in evidence/mandarin. The accelerated
cohort's original 420 recordings and its 20 transformations have separate totals.
Each model is scored only on an entire declared set, including empty outputs.
"""
import argparse
import collections
import hashlib
import json
import re
from pathlib import Path
import runpy

root = Path(__file__).resolve().parents[2]
score = runpy.run_path(str(root / "scripts/mandarin/score.py"))
base = score["base"]
models = ["apple", "sherpa", "qwen-small", "qwen-large"]
derived = {"quiet", "noise15db"}


def load(file):
    return json.loads(file.read_text())


def sha(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def publication_evidence(manifest, receipts, observations):
    """A view can reveal one publication in several frames. Count the source as well."""
    counts, gaps, mismatches = [], [], []
    def pairs(s): return set(zip(s, s[1:]))
    for source, path, observed in zip(manifest, receipts, observations, strict=True):
        receipt = load(path)
        reference = pairs(base["norm"](source["reference"]))
        times = []
        previous = set()
        for item in receipt["publications"]:
            current = pairs(base["norm"](item["text"]))
            if observed["onset"] <= item["t"] < min(observed["active_end"], receipt["endOfFile"]):
                if (current - previous) & reference:
                    times.append(item["t"])
            previous = current
        counts.append(len(times))
        gaps.extend(right - left for left, right in zip(times, times[1:]))
        archived = "".join(reversed(receipt["archive"]))
        latest = [(receipt[field][-1]["text"] if receipt[field] else "") for field in ("publications", "frames")]
        if not archived or any(archived != text for text in latest):
            mismatches.append(source["id"])
    return {"clips_with_two_or_more_meaningful_publications": sum(n >= 2 for n in counts),
            "range_of_meaningful_publications": [min(counts), max(counts)],
            "publication_gap_seconds": base["quant"](gaps), "verbatim_final_mismatches": mismatches}


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--receipts", type=Path, required=True)
    cli.add_argument("--wav", type=Path, required=True)
    cli.add_argument("--out", type=Path, required=True)
    cli.add_argument("--source", required=True)
    args = cli.parse_args()
    fixtures = root / "evidence/mandarin"
    cohort = {group: load(fixtures / (group + ".json")) for group in ["paired", "aishell"]}
    panel = load(fixtures / "panel-cohort.json")["samples"]
    summary = {"source": args.source, "panels": {}, "accelerated": {}, "files_sha256": {}}
    for model in models:
        place = args.receipts / "panels"
        panels = [place / f"{model}-{row['id']}.json" for row in panel]
        if all(path.exists() for path in panels):
            for p in panels:
                row = load(p)
                allowed = {"apple-speech-analyzer" if model == "apple" else model}
                assert row["model"] == model and set(row["providers"]) <= allowed, p
                summary["files_sha256"][str(p.relative_to(args.receipts))] = sha(p)
            result = score["windows"](model, place, panel, args.wav, args.source)
            failures = []
            for ref, receipt in zip(panel, panels, strict=True):
                frames = load(receipt)
                if frames["exit_code"] or not any(line.strip() for line in frames["archive"]):
                    failures.append({"id": ref["id"], "exit_code": frames["exit_code"],
                                     "providers": frames["providers"]})
            result["failed_or_empty"] = failures
            result["publication_evidence"] = publication_evidence(panel, panels, result["rows"])
            summary["panels"][model] = result
        for method in ["direct", "product"]:
            reports = {}
            scored = collections.defaultdict(collections.Counter)
            anchors = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
            for group, rows in cohort.items():
                p = args.receipts / "runs" / f"{group}-{model}-{method}.jsonl"
                if not p.exists():
                    continue
                reports[group] = score["transcriptions"](p, rows)
                summary["files_sha256"][str(p.relative_to(args.receipts))] = sha(p)
                for ref, line in zip(rows, p.read_text().splitlines(), strict=True):
                    heard = json.loads(line)
                    assert heard["model"] == model and heard["path"] == method
                    result = base["rating"](ref["reference"], heard["text"])
                    key = "derived_20" if ref["source"] in derived else "original_420"
                    scored[key].update(result)
                    scored[key]["rows"] += 1
                    # Exact surface-token counts are diagnostics even when the same
                    # number was spoken but the recognizer formatted it differently.
                    for category, pattern in score["categories"].items():
                        wanted, observed = [
                            collections.Counter(
                                base["norm"](token) for token in re.findall(pattern, text, flags=re.I)
                            )
                            for text in (ref["reference"], heard["text"])
                        ]
                        anchors[key][category].update({
                            "reference": wanted.total(), "missing": (wanted - observed).total(),
                            "extra": (observed - wanted).total(),
                        })
            if reports:
                summary["accelerated"][f"{model}-{method}"] = {
                    "by_manifest": reports,
                    "exact_anchor_tokens": {
                        key: counts for key, counts in anchors.items()
                        if scored[key]["rows"] == (20 if key == "derived_20" else 420)
                    },
                    "cohorts": {
                        key: dict(**base["pooled"](v), rows=v["rows"])
                        for key, v in scored.items()
                        if v["rows"] == (20 if key == "derived_20" else 420)
                    },
                }
    summary["resources"] = {}
    for model in models:
        p = args.receipts / "resources" / f"{model}.json"
        if not p.is_file():
            continue
        physical = load(p)
        assert physical["source"] == args.source and physical["model"] == model, p
        assert physical["wave"] in {r["audio_sha256"] for r in panel}, p
        active, idle = physical["active"], physical["idle"]
        assert active["probe_exit"] == 0 and physical["window_updates"] >= 2, p
        def cpu_percent(snapshot):
            rates = [r["cpu_percent"] for field in ("app", "helper") for r in snapshot[field]
                     if r.get("cpu_percent") is not None]
            return sum(rates)
        summary["resources"][model] = {
            "app_and_helper_simultaneous_peak_MiB": round(active["app_and_helper_simultaneous_peak_bytes"] / 2**20, 2),
            "cpu_percent_app_and_helper": base["quant"]([cpu_percent(frame) for frame in active["snapshots"]]),
            "apple_shared_recognizer_peak_MiB": round(active["peak_bytes"]["speech"] / 2**20, 2),
            "seconds": active["observed_seconds"],
            "idle_mean": idle["mean"], "active_mean": active["mean"],
            "system_W_above_adjacent_idle": round(active["mean"]["sys_power"] - idle["mean"]["sys_power"], 3),
            "samples_active": len(active["telemetry"]), "samples_idle": len(idle["telemetry"]),
        }
        summary["files_sha256"][str(p.relative_to(args.receipts))] = sha(p)
    args.out.write_text(json.dumps(summary, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
    main()
