"""Aggregate matched human references and physical-window observations. Retain empty outputs."""

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re
import runpy

root = Path(__file__).resolve().parents[2]
base = runpy.run_path(str(root / "scripts/score-local-asr.py"))
rate, norm, quant = (base[k] for k in ("rating", "norm", "quant"))
folder = root / "evidence/mandarin"
categories = {
    "number": r"[0-9]+(?:[.,][0-9]+)*|[零〇一二两三四五六七八九十百千万亿]+",
    "negative": r"不能|不会|不要|没有|并非|不|没|无|非",
    "money": r"人民币|美元|欧元|港币|元|块钱",
    "date_time": r"年|月|号|星期|小时|分钟|秒钟|点钟",
    "latin": r"[A-Za-z]{2,}",
    "technical_term": r"人工智能|算法|计算机|引擎|处理器|服务器|网络|软件|疫苗|病毒|AI\b|DNA\b",
}


def read(path):
    return json.loads(path.read_text())


def transcriptions(path, rows):
    raw = [json.loads(line) for line in path.read_text().splitlines()]
    assert [r["id"] for r in raw] == [r["id"] for r in rows], path
    by_source = defaultdict(Counter)
    failures = Counter()
    anchors = defaultdict(Counter)
    mixed = Counter()
    for result, item in zip(raw, rows):
        hyp = result["text"]
        assert set(result.get("providers", [])) <= {
            ("apple-speech-analyzer" if result["model"] == "apple" else result["model"])
        }
        if item["source"] == "ascend-mixed":
            tokens = base["V1"]["tokenize"]
            mixed.update(
                base["align"](tokens(item["reference"], "mer"), tokens(hyp, "mer"))
            )
        failures["empty_rows"] += not bool(hyp.strip())
        failures["rows_with_failed_segment"] += "failed" in result.get("states", [])
        for key in [item["source"], "ALL"]:
            by_source[key].update(rate(item["reference"], hyp))
            by_source[key]["rows"] += 1
        for category, pattern in categories.items():
            occurrences = Counter(
                norm(v) for v in re.findall(pattern, item["reference"], re.I)
            )
            for token, count in occurrences.items():
                if token:
                    anchors[category]["literal_matched"] += min(
                        norm(hyp).count(token), count
                    )
                    anchors[category]["reference_occurrences"] += count
    return dict(
        rows=len(rows),
        failures=failures,
        literal_anchors=anchors,
        mixed_mer={
            "reference_units": mixed["reference_units"],
            "errors": mixed["errors"],
            "mer": mixed["errors"] / mixed["reference_units"]
            if mixed["reference_units"]
            else None,
        },
        groups={
            g: dict(**base["pooled"](c), rows=c["rows"]) for g, c in by_source.items()
        },
    )


def windows(model, panel_folder, samples, wav, sha, *, automatic=False):
    observations = []
    gaps = []
    for item in samples:
        label = ("auto-" if automatic else "") + model
        result = read(panel_folder / (label + "-" + item["id"] + ".json"))
        assert result["sha"] == sha and result["audio_sha256"] == item["audio_sha256"]
        if automatic:
            assert result["automatic"] is True and result["model"] == model
        onset, end = base["acoustic"](wav / (item["id"] + ".wav"))
        reference = norm(item["reference"])
        ref_pairs = set(zip(reference, reference[1:]))
        distinct, meaningful, previous = [], [], ""
        for f in result["frames"]:
            current = norm(f["text"])
            if not (
                onset <= f["t"] < min(result["endOfFile"], end)
                and f["speaking"]
                and current
                and current != previous
            ):
                continue
            distinct.append((f["t"], current))
            pairs = set(zip(current, current[1:]))
            if (pairs - set(zip(previous, previous[1:]))) & ref_pairs:
                meaningful.append(f["t"])
            previous = current
        gaps.extend(b - a for a, b in zip(meaningful, meaningful[1:]))
        times = [onset] + meaningful + [end]
        final = "".join(reversed(result["archive"]))
        observations.append(
            dict(
                id=item["id"],
                exit=result["exit_code"],
                providers=result["providers"],
                duration=item["duration"],
                meaningful=len(meaningful),
                onset=onset,
                active_end=end,
                first_lexical=distinct[0][0] - onset if distinct else None,
                first_meaningful=meaningful[0] - onset if meaningful else None,
                longest_stall=max(b - a for a, b in zip(times, times[1:])),
                final_after_file=result["pipelineSettledAt"] - result["endOfFile"]
                if "pipelineSettledAt" in result
                else None,
                final_after_acoustic=result["pipelineSettledAt"] - end
                if "pipelineSettledAt" in result
                else None,
                churn=base["changes"]([text for _, text in distinct]),
                archive=rate(reference, final),
            )
        )
    cnt = Counter()
    for row in observations:
        cnt.update(row["archive"])
    return dict(
        rows=observations,
        observations=len(observations),
        multi=sum(r["meaningful"] >= 2 for r in observations),
        multiple_on_long=[
            sum(r["duration"] >= 10 and r["meaningful"] >= 2 for r in observations),
            sum(r["duration"] >= 10 for r in observations),
        ],
        missing_meaningful=sum(r["first_meaningful"] is None for r in observations),
        first_lexical=quant(
            [r["first_lexical"] for r in observations if r["first_lexical"] is not None]
        ),
        first_meaningful=quant(
            [
                r["first_meaningful"]
                for r in observations
                if r["first_meaningful"] is not None
            ]
        ),
        gaps=quant(gaps),
        longest_stall=quant([r["longest_stall"] for r in observations]),
        after_acoustic=quant(
            [
                r["final_after_acoustic"]
                for r in observations
                if r["final_after_acoustic"] is not None
            ]
        ),
        after_file=quant(
            [
                r["final_after_file"]
                for r in observations
                if r["final_after_file"] is not None
            ]
        ),
        churn=sum(r["churn"]["tail_replacements"] for r in observations),
        archive=base["pooled"](cnt),
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--wav", type=Path, required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--results", type=Path, default=folder)
    args = parser.parse_args()
    run_folder = args.results
    result = {"app_source": args.sha, "quality": {}, "windows": {}}
    for cohort in ["paired", "aishell"]:
        path = folder / (cohort + ".json")
        assert path.exists(), path
        rows = read(path)
        result["quality"][cohort] = {}
        for f in sorted((run_folder / "runs").glob(cohort + "-*.jsonl")):
            result["quality"][cohort][f.stem.removeprefix(cohort + "-")] = (
                transcriptions(f, rows)
            )
        expected = {
            m + "-" + method
            for m in ("apple", "sherpa", "qwen-small", "zipformer")
            for method in ("direct", "product")
        }
        assert set(result["quality"][cohort]) == expected, cohort
    samples = read(folder / "panel-cohort.json")["samples"]
    for model in ["apple", "sherpa", "qwen-small", "zipformer"]:
        result["windows"][model] = windows(
            model, run_folder / "panels", samples, args.wav, args.sha
        )
    old = run_folder / "baseline-panels"
    if old.exists():
        oldsha = read(next(old.glob("*.json")))["sha"]
        result["qwen_baseline"] = windows("qwen-small", old, samples, args.wav, oldsha)
        result["baseline_app_source"] = oldsha
    (run_folder / "comparison.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=1) + "\n"
    )
