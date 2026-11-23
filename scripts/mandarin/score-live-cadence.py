"""Measure real progress in the ASR timeline independently of AppKit animation.

Inputs are native --local-stream-probe receipts and their public manifest.
A useful event adds a reference bigram never previously observed in that layer.
The original 0.13 metric (new relative to only the preceding event) is also
reported. A late repaint or oscillation cannot create new ASR progress.
"""
import argparse
import hashlib
import json
from pathlib import Path
import runpy
import wave
from array import array

score = runpy.run_path(str(Path(__file__).resolve().parents[1] / "score-local-asr.py"))
norm, quant = score["norm"], score["quant"]


def active_blocks(audio):
    with wave.open(str(audio)) as wav:
        assert (wav.getnchannels(), wav.getframerate(), wav.getsampwidth()) == (1, 16000, 2)
        samples = array("h", wav.readframes(wav.getnframes()))
    floor = (32768 * 10 ** (-55 / 20)) ** 2
    return [sum(x * x for x in samples[i:i + 320]) >= len(samples[i:i + 320]) * floor
            for i in range(0, len(samples), 320)]


def bigrams(text):
    text = norm(text)
    return set(zip(text, text[1:]))


def layer_events(events, reference, onset, end, visible):
    seen, previous = set(), set()
    fresh, conventional = [], []
    first_seen = {}
    for item in events:
        at = item["t"]
        if at < onset or at >= end or (visible and not item["speaking"]):
            continue
        if item.get("kind") == "ready":
            continue
        words = bigrams(item["text"])
        if reference is not None:
            words.intersection_update(reference)
        if words - previous:
            conventional.append(at)
        if words - seen:
            fresh.append(at)
            for word in words - seen:
                first_seen[word] = at
        previous = words
        seen.update(words)
    return conventional, fresh, first_seen


def gaps(times):
    return [b - a for a, b in zip(times, times[1:])]


def describe(times, onset, end, activity, raw, timeline):
    spans = list(zip([onset, *times], [*times, end]))
    longest = max(spans, key=lambda x: x[1] - x[0])
    a, b = longest
    active = [value for i, value in enumerate(activity) if a <= (i + .5) * .02 < b]
    within = lambda events: sum(a < item["t"] < b and bool(item["text"]) for item in events)
    return dict(count=len(times), first_s=round(times[0] - onset, 3) if times else None,
                gap_s=quant(gaps(times)), longest_s=round(b - a, 3),
                longest_start_end_s=[round(a, 3), round(b, 3)],
                longest_position="first" if a == onset else "last" if b == end else "interior",
                longest_input_above_minus55_fraction=round(sum(active) / len(active), 3) if active else None,
                raw_outputs_inside_longest=within(raw) if raw is not None else None,
                timeline_outputs_inside_longest=within(timeline),
                above_two_seconds=sum(y - x >= 2 for x, y in spans))


def describe_decodes(events, origin, gap):
    # Timings are sent in the next worker message, even for intervening
    # decodes which produced exactly the prior text. Compare monotonic clocks.
    decode = [(d["startUptime"] - origin, d["endUptime"] - origin, d["final"])
              for event in events for d in (event.get("decodes") or [])]
    assert all(end >= start for start, end, _ in decode)
    starts = [start for start, _, final in decode if not final]
    durations = [end - start for start, end, final in decode if not final]
    a, b = gap
    return dict(previews=len(starts), final_decodes=sum(final for _, _, final in decode),
                preview_compute_s=quant(durations), preview_compute_sum_s=round(sum(durations), 4),
                preview_start_intervals_s=quant(gaps(starts)),
                previews_finishing_during_longest_timeline_gap=sum(a < end < b and not final for _, end, final in decode))


def measure(manifest, audio, receipts, sha):
    rows, pools, raw_to_timeline, timeline_to_display = [], {}, [], []
    entries = json.loads(manifest.read_text())["samples"]
    for ref in entries:
        ident = ref["id"]
        result = json.loads((receipts / f"auto-qwen-small-{ident}.json").read_text())
        wav = audio / (ident + ".wav")
        assert result["sha"] == sha and result["automatic"] and result["providers"] == ["qwen-small"]
        assert result["audio_sha256"] == ref["audio_sha256"] == hashlib.sha256(wav.read_bytes()).hexdigest()
        onset, end = score["acoustic"](wav)
        end = min(end, result["endOfFile"])
        timeline, raw = result["publications"], result.get("rawWorkerEvents")
        series = {"timeline": timeline, "display": result["frames"]}
        if raw is not None:
            series["worker"] = raw
        active = active_blocks(wav)
        archive = "".join(reversed(result["archive"]))
        reference = ref.get("reference")
        if reference is None:
            # A separately tested truncated long fixture has no exact transcript.
            # Track literal output changes and withhold reference-based CER.
            supported_pairs = None
        else:
            supported_pairs = bigrams(reference)
        row = dict(id=ident, sha256=ref["audio_sha256"], onset=onset, end=end,
                   reference_available=reference is not None,
                   final_CER=score["rating"](reference, archive) if reference is not None else None,
                   matches_final_window=bool(result["frames"]) and result["frames"][-1]["text"] == archive,
                   records=result["recordStates"], after_file_s=round(result["pipelineSettledAt"]-result["endOfFile"], 3),
                   after_last_signal_s=round(result["pipelineSettledAt"]-end, 3))
        layers = {}
        for layer, events in series.items():
            old, once, first_seen = layer_events(events, supported_pairs, onset, end, layer == "display")
            layers[layer] = first_seen
            row[layer] = describe(once, onset, end, active, raw, timeline)
            for kind, times in [("first_seen", once), ("previous_event", old)]:
                key = layer + "_" + kind
                pools.setdefault(key, []).extend(gaps(times))
        for earlier, later, values in [("worker", "timeline", raw_to_timeline), ("timeline", "display", timeline_to_display)]:
            if earlier in layers:
                shared = layers[earlier].keys() & layers[later].keys()
                values.extend(layers[later][p] - layers[earlier][p] for p in shared)
        if raw is not None and "clockOriginUptime" in result:
            row["decode"] = describe_decodes(raw, result["clockOriginUptime"], row["timeline"]["longest_start_end_s"])
        rows.append(row)
    summary = {}
    for layer in series:
        metrics = [row[layer] for row in rows]
        summary[layer] = dict(fresh_gaps_s=quant(pools[layer + "_first_seen"]),
                              previous_event_gaps_s=quant(pools[layer + "_previous_event"]),
                              longest_per_clip_s=quant([m["longest_s"] for m in metrics]),
                              first_s=quant([m["first_s"] for m in metrics if m["first_s"] is not None]),
                              clips_with_repeated_updates=sum(m["count"] >= 2 for m in metrics),
                              number_of_gaps_at_least_2s=sum(m["above_two_seconds"] for m in metrics))
    return dict(source=sha, clips=len(rows), reference_checked_clips=sum(r["reference_available"] for r in rows),
                summary=summary, rows=rows,
                matched_bigram_delay_s={"worker_to_timeline":quant(raw_to_timeline),
                                        "timeline_to_display":quant(timeline_to_display)})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ["manifest", "audio", "receipts", "out"]:
        parser.add_argument("--" + flag, required=True, type=Path)
    parser.add_argument("--sha", required=True)
    params = parser.parse_args()
    result = measure(params.manifest, params.audio, params.receipts, params.sha)
    params.out.parent.mkdir(parents=True,exist_ok=True)
    params.out.write_text(json.dumps(result,ensure_ascii=False,indent=2) + "\n")
