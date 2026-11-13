"""Paired source-publication and screen measurements on identical public audio.

Track first appearance of healthy reference bigrams. The fixed reference is
untimed, so early/late are relative to the other build, never to a human label.
"""
import argparse
from bisect import bisect_right
from collections import Counter
from functools import lru_cache
from math import ceil
import json
from pathlib import Path
import runpy

scorer = runpy.run_path(str(Path(__file__).with_name("score-live-cadence.py")))
quant, bigrams = (scorer[key] for key in ("quant", "bigrams"))


def first_appearance(events, wanted, end):
    first = {}
    for event in events:
        if event["t"] > end:
            continue
        for pair in bigrams(event["text"]) & wanted:
            first.setdefault(pair, event["t"])
    return first


@lru_cache(maxsize=2048)
def closest_reference_prefix_errors(text, reference):
    # Endpoint-free only on the reference side. A genuine word-time transcript
    # is unavailable; never call this diagnostic ordinary whole-utterance CER.
    previous = list(range(len(reference) + 1))
    for i, char in enumerate(text, 1):
        current = [i]
        for j, target in enumerate(reference, 1):
            current.append(min(previous[j] + 1, current[-1] + 1,
                               previous[j - 1] + (char != target)))
        previous = current
    return min(previous)


def sampled_preview_errors(old, new, reference):
    normalize = scorer["norm"]
    reference = normalize(reference)
    timelines = [[(ev["t"], normalize(ev["text"])) for ev in data["frames"] if ev["text"]]
                 for data in (old, new)]
    if any(not events for events in timelines):
        return {}
    totals = {"old": Counter(), "new": Counter()}
    start = max(events[0][0] for events in timelines)
    end = min(data["endOfFile"] for data in (old, new))
    for timestamp in range(ceil(start * 10), ceil(end * 10)):
        t = timestamp / 10
        for label, events in zip(totals, timelines, strict=True):
            i = bisect_right(events, t, key=lambda ev: ev[0]) - 1
            text = events[i][1]
            totals[label].update(errors=closest_reference_prefix_errors(text, reference),
                                 displayed_characters=len(text), timepoints=1)
    return dict(totals)


def compare(manifest, old_dir, new_dir):
    results, delays = [], {"publications": [], "frames": []}
    sources = set()
    for source in json.loads(manifest.read_text())["samples"]:
        name = f'auto-qwen-small-{source["id"]}.json'
        old, new = (json.loads((d / name).read_text()) for d in (old_dir, new_dir))
        sources.add((old["sha"], new["sha"]))
        assert all(x["audio_sha256"] == source["audio_sha256"] and x["exit_code"] == 0 for x in (old, new))
        assert all(x["automatic"] and x["providers"] == ["qwen-small"] for x in (old, new))
        end = min(x["endOfFile"] for x in (old, new))
        row = {"id": source["id"], "sha256": source["audio_sha256"], "same_archive": old["archive"] == new["archive"]}
        for layer, all_deltas in delays.items():
            wanted = bigrams(source["reference"])
            before, after = (first_appearance(x[layer], wanted, end) for x in (old, new))
            shared = before.keys() & after.keys()
            change = [before[word] - after[word] for word in sorted(shared)]
            all_deltas.extend(change)
            row[layer] = dict(shared=len(shared), new_only=len(after.keys() - before.keys()),
                              old_only=len(before.keys() - after.keys()), seconds_earlier=quant(change))
        row["sampled_preview_errors"] = sampled_preview_errors(old, new, source["reference"])
        results.append(row)
    if len(sources) != 1 or len(results) != len({row["id"] for row in results}):
        raise ValueError("Expected a single source revision per candidate and one receipt per clip")
    before_sha, after_sha = sources.pop()
    metrics = {}
    for key, delta in delays.items():
        metrics[key] = dict(paired_bigram_occurrences=len(delta), seconds_earlier=quant(delta),
                            more_than_250ms_earlier=sum(d > .25 for d in delta),
                            more_than_250ms_later=sum(d < -.25 for d in delta),
                            new_only=sum(r[key]["new_only"] for r in results),
                            old_only=sum(r[key]["old_only"] for r in results))
    sampled = {}
    for label in ("old", "new"):
        combined = sum((Counter(row["sampled_preview_errors"].get(label, {})) for row in results), Counter())
        sampled[label] = dict(combined, errors_per_displayed_character=round(combined["errors"] /
                                       combined["displayed_characters"], 5) if combined["displayed_characters"] else None)
    return dict(sampled_preview_errors=sampled, baseline=before_sha, candidate=after_sha, identical_archives=sum(r["same_archive"] for r in results),
                clips=len(results), summary=metrics, rows=results)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ("manifest", "old", "new", "output"):
        p.add_argument("--" + arg, type=Path, required=True)
    args = p.parse_args()
    args.output.write_text(json.dumps(compare(args.manifest, args.old, args.new), ensure_ascii=False, indent=2) + "\n")
