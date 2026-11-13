#!/usr/bin/env python3
"""Check whether later VAD timestamps coincide with missing reference boundaries.

The first/last six normalized characters are secondary literal indicators. No
manual correction, alternate spelling, filtering of difficult cases, or forced
alignment. These metrics cannot localize an acoustic error to VAD or ASR.
"""
import json
from pathlib import Path
import runpy

repo = Path(__file__).resolve().parents[2]
evidence = repo / "evidence/mandarin-quality-20261114"
corpus = repo / "evidence/mandarin"
scorer = runpy.run_path(str(repo / "scripts/score-local-asr.py"))


def rows(path):
    return {record["id"]: record for record in map(json.loads, path.read_text().splitlines())}


def inspect(text, reference):
    hyp = scorer["norm"](text)
    ref = scorer["norm"](reference)
    width = min(6, len(ref))
    assert width > 0
    return dict(head=hyp[:width], tail=hyp[-width:], head_matches=hyp.startswith(ref[:width]),
                tail_matches=hyp.endswith(ref[-width:]), **scorer["rating"](ref, hyp))


def summarize(checked):
    return dict(clips=len(checked), head_exact=sum(r["head_matches"] for r in checked),
                tail_exact=sum(r["tail_matches"] for r in checked),
                edits=sum(r["errors"] for r in checked),
                units=sum(r["reference_units"] for r in checked))


def main():
    refs = json.loads((corpus / "paired.json").read_text()) + json.loads((corpus / "aishell.json").read_text())
    splits = rows(evidence / "segmentation-frames.jsonl")
    sets = {}
    for name, folder, engine in [("candidate_qwen", "candidate", "qwen-small"),
                                  ("candidate_qwen_auto", "unforced", "qwen-small"),
                                  ("baseline_apple", "baseline", "apple"),
                                  ("baseline_qwen", "baseline", "qwen-small")]:
        primary = evidence / folder / "runs"
        files = [primary / f"{part}-{engine}-product.jsonl" for part in ("paired", "aishell")]
        if name == "baseline_qwen" and not all(f.exists() for f in files):
            continue
        batches = [rows(f) for f in files]
        assert not batches[0].keys() & batches[1].keys()
        sets[name] = batches[0] | batches[1]
    assert all(len(results) == len(splits) == len(refs) == 440 for results in sets.values())
    cohorts, delayed = {}, []
    for row in refs:
        key, split = row["id"], splits[row["id"]]
        assert row["audio_sha256"] == split["wav_sha256"]
        measurements = {name: inspect(data[key]["text"], row["reference"]) for name, data in sets.items()}
        cohorts.setdefault(row["source"], []).append(measurements)
        if len(split["candidate"]) == len(split["baseline"]) == 1:
            offset = split["candidate"][0]["firstVoiceSample"] - split["baseline"][0]["firstVoiceSample"]
            if offset >= 16000:
                norm = scorer["norm"](row["reference"])
                delayed.append(dict(id=key, wav_sha256=row["audio_sha256"], later_samples=offset,
                                    ref_head=norm[:6], ref_tail=norm[-6:], results=measurements))
    output = dict(criterion="First/last min(6, reference length) normalized characters match at the exact text boundary; CER edits from the established scorer.",
                  tracks=list(sets), onset_delay_at_least_one_second=delayed,
                  by_corpus={c: {name: summarize([r[name] for r in data]) for name in sets}
                             for c, data in cohorts.items()})
    print(json.dumps(output, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
