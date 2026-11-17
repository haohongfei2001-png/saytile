"""Recompute the two different longest intervals from the existing native 38.8 s crossover.

From the Saytile repository: python3 evidence/next-release-recognition/loaded-gap/decompose.py
No model, audio playback, account or private recording is accessed.
"""

import gzip
import hashlib
import json
import runpy
from pathlib import Path

repo = Path.cwd()
evidence = repo / "evidence/next-release-recognition"


def read(path):
    return json.loads(path.read_bytes())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rounded(value):
    return round(value, 6)


raw_path = evidence / "crossover38s.jsonl.gz"
summary_path = evidence / "crossover38s-metrics.json"
clip_path = repo / "evidence/mandarin/continuous.json"
scorer_path = repo / "scripts/mandarin/score-live-cadence.py"
scorer = runpy.run_path(str(scorer_path))
index = {q["run"]: q for q in read(summary_path)}
traces = {v["run"]: v for v in map(json.loads, gzip.decompress(raw_path.read_bytes()).splitlines())}
target = traces["B-9-2"]
native = target["native"]
pcm = read(clip_path)["samples"][0]
assert native["audio_sha256"] == pcm["audio_sha256"]
reference_pairs = scorer["bigrams"](pcm["reference"])
origin = native["clockOriginUptime"]
raw = native["rawWorkerEvents"]


def layer_changes(events, is_display=False):
    seen = set()
    rows = []
    for event in events:
        if event.get("kind") == "ready" or is_display and not event["speaking"]:
            continue
        pairs = scorer["bigrams"](event["text"]) & reference_pairs
        rows.append(
            dict(
                t=event["t"],
                new=sorted("".join(p) for p in pairs - seen),
                text=event["text"],
                kind=event.get("kind"),
                frames=event.get("frames"),
            )
        )
        seen.update(pairs)
    return rows


def widest_inner(rows):
    times = [r["t"] for r in rows if r["new"] and r["t"] < native["endOfFile"]]
    return max(zip(times, times[1:]), key=lambda p: p[1] - p[0])


def intervals(rows, start, end):
    return [
        dict(
            t=rounded(r["t"]),
            newReferencePairs=r["new"],
            kind=r["kind"],
            frames=r["frames"],
            suffix=r["text"][-23:],
        )
        for r in rows
        if start <= r["t"] <= end
    ]


workers = layer_changes(raw)
timeline = layer_changes(native["publications"])
display = layer_changes(native["frames"], True)
wa, wb = widest_inner(workers)
da, db = widest_inner(display)
reference = index[target["run"]]
assert [round(t, 3) for t in (wa, wb)] == reference["worker"]["longest_start_end_s"]
assert [round(t, 3) for t in (da, db)] == reference["display"]["longest_start_end_s"]
end_i = next(i for i, e in enumerate(raw) if e["t"] == wb)
left, right = raw[end_i - 1 : end_i + 1]
assert left["t"] == wa and left["kind"] == "partial" and right["kind"] == "final"
times = [
    (event, timing, timing["startUptime"] - origin, timing["endUptime"] - origin)
    for event in raw
    for timing in event.get("decodes", [])
]
intersect = [(e, d, a, b) for e, d, a, b in times if min(wb, b) > max(wa, a)]
assert len(intersect) == 1
event, dec, start, end = intersect[0]
assert (
    dec["final"]
    and dec["changed"]
    and dec["frames"] == right["frames"]
    and event["t"] == wb
    and wa < start < end < wb
)
last = left["decodes"][-1]
assert not last["final"] and left["frames"] == last["frames"] and last["verifiedPreviewTokens"] > 0
next_event = raw[end_i + 1]
assert next_event["kind"] == "partial" and next_event["frames"] < right["frames"]
final_timeline = next(e["t"] for e in native["publications"] if e["t"] >= wb and "声光" in e["text"][-5:])
final_window = next(e["t"] for e in native["frames"] if e["t"] >= wb and "声光" in e["text"][-5:])
in_gap = [r for r in workers if da < r["t"] < db]
assert len(in_gap) == 4
# Match the source events around the visible endpoints. A model/host event for the
# right endpoint occurs just before the display samples it, so do not treat it as withheld.
pub_left, pub_right = widest_inner(timeline)
assert round(pub_right - pub_left, 3) == reference["timeline"]["longest_s"]
changed = [r for r in in_gap if r["new"]]
history_path = repo / "evidence/mandarin-preview-20261114/followup/worker-blocks-474/scheduler-trial.json"
history = read(history_path)
prior = evidence / "publication-evidence.json"
draft_path = repo / "evidence/mandarin-preview-20261114/draft-verification.json"
assert read(draft_path)["exact_token_outputs"] == 14
siblings = []
for name, trace in traces.items():
    ne = trace["native"]
    fs = [d for e in ne["rawWorkerEvents"] for d in e.get("decodes", []) if d["final"]]
    assert (
        len(fs) == 2
        and all(e["final"] for e in fs)
        and fs[0]["frames"] == 481280
        and fs[1]["frames"] == 139520
    )
    assert ne["archive"] == native["archive"] and ne["audio_sha256"] == native["audio_sha256"]
    measurement = index[name]
    siblings.append(
        dict(
            run=name,
            source=ne["sha"],
            inputs=ne["recordStates"],
            addedLoadWorkers=9 if measurement["load"] else 0,
            measuredLoadEquivalentCores=(measurement["load"] or {}).get("observed_cores"),
            firstSegmentFinalWallSeconds=rounded(fs[0]["endUptime"] - fs[0]["startUptime"]),
            fileLastSegmentFinalWallSeconds=rounded(fs[1]["endUptime"] - fs[1]["startUptime"]),
            workerLongestSeconds=measurement["worker"]["longest_s"],
            windowLongestSeconds=measurement["display"]["longest_s"],
            combinedAppAndWorkerCpuSeconds=trace["process"]["combined_cpu_s"],
            peakSimultaneousFootprintMiB=trace["process"]["peak_simultaneous_footprint_MiB"],
        )
    )
report = {
    "attribution": "Existing original-rate M5 native trace B-9-2, no new workload or model experiment.",
    "measuredSource": native["sha"],
    "measuredRelease": "Isolated 4c19982 ASR candidate derived from build 497. The most recent 533 build did not repeat this load.",
    "input": {
        "id": native["id"],
        "duration_s": pcm["duration"],
        "sha256": pcm["audio_sha256"],
        "description": pcm["source"],
        "sampleRate": 16000,
    },
    "method": {
        "clock": "Worker startUptime/endUptime minus the native probe clockOriginUptime. Raw event times are host read times. AppKit samples actual string changes; progress requires the first occurrence of a reference bigram in that layer.",
        "intervals": "Enumerate adjacent first-occurrence timestamps on each layer; cross-check the winning interval against the original score. Intersect every decode, including unchanged ones batched inside subsequent events, with the precise worker interval. Half-open endpoints avoid attributing a preceding pass twice.",
        "cpuLimits": "Decoder duration is elapsed wall time around transcribe(samples). It includes CPU running, GPU/Metal waits and descheduling. Original ps counters are process-wide, at ~200ms intervals with a different time-zero. There are no per-thread on/off-CPU, QoS or GPU counters for the pass. Its wall-time split by cause is not available.",
    },
    "workerPause": {
        "first_s": rounded(wa),
        "last_s": rounded(wb),
        "wall_ms": rounded((wb - wa) * 1000),
        "delta_ms": {
            "previousEventReceiptToDecodeStart": rounded((start - wa) * 1000),
            "insideOneExactFullSegmentDecode": rounded((end - start) * 1000),
            "decodeEndToHostReceipt": rounded((wb - end) * 1000),
        },
        "decodeCoveragePercent": rounded(100 * (end - start) / (wb - wa)),
        "decodeStart_s": rounded(start),
        "decodeEnd_s": rounded(end),
        "numberIntersectingDecodes": len(intersect),
        "otherRawEventsStrictlyInside": sum(wa < e["t"] < wb for e in raw),
        "previousPreview": {
            "frames": left["frames"],
            "verifiedPreviewTokens": last["verifiedPreviewTokens"],
        },
        "segmentEOS": {
            "frames": right["frames"],
            "audioSeconds": right["frames"] / 16000,
            "extraPCMFramesSincePreview": right["frames"] - left["frames"],
            "extraAudioSecondsSincePreview": (right["frames"] - left["frames"]) / 16000,
            "verifiedPreviewTokens": dec["verifiedPreviewTokens"],
            "changed": dec["changed"],
        },
        "sourceAndFinal": intervals(workers, wa, wb),
        "finalReceiptToTimeline_ms": rounded((final_timeline - wb) * 1000),
        "finalReceiptToAppKit_ms": rounded((final_window - wb) * 1000),
        "firstFollowingSegmentCandidate_s": rounded(next_event["t"]),
        "firstFollowingSegmentCandidateDelayAfterPreviousFinal_ms": rounded(
            1000 * (next_event["t"] - wb)
        ),
        "fileEOS_s": rounded(native["endOfFile"]),
    },
    "differentDisplayPause": {
        "range_s": [rounded(da), rounded(db)],
        "wall_s": rounded(db - da),
        "timelineRange_s": [rounded(pub_left), rounded(pub_right)],
        "workerCandidatesInsideDisplayRange": intervals(workers, da, db),
        "timelineItems": intervals(timeline, pub_left, pub_right),
        "appKitFrames": intervals(display, da, db),
        "publishedLiteralChangeWithoutNovelReferencePair_s": rounded(
            next(r["t"] for r in display if da < r["t"] < db and not r["new"])
        ),
        "rightEndpointRawToTimeline_ms": rounded((pub_right - changed[-1]["t"]) * 1000),
        "rightEndpointRawToAppKit_ms": rounded((db - changed[-1]["t"]) * 1000),
        "observation": "23.172s shows a changed string, with no previously unseen reference bigram. At 24.244s and 25.168s the worker brings new reference pairs with competing earlier wording; the timeline does not publish those observations. At 25.765s a supported longer observation arrives. UI delivery follows promptly. This 3.429s metric is a gap in reference-confirmed progress, not a literal frame freeze. Withholding provenance is inferred from the candidates and tested gate, not from a logged rejection code.",
    },
    "crossovers": siblings,
    "archiveCER": reference["archive"],
    "history": {
        "schedulerTrial": {
            "record": str(history_path.relative_to(repo)),
            "variable": history["change"],
            "result": history["decision"],
            "clarification": "The qos labels here belong to the external load workers. This comparison changed the preview interval, not the recognition child QoS.",
        },
        "verifiedDraft": {
            "record": str(draft_path.relative_to(repo)),
            "agreedPreviewTokens": read(draft_path)["exact_token_outputs"],
            "comparisons": read(draft_path)["outputs"],
            "reason": "Block-verified preview may produce a different token sequence than exact scalar decoding. It is not a proven substitute for finalization; in the sampled pause PCM also grew by 680 ms.",
        },
        "unstablePreview": {
            "record": str(prior.relative_to(repo)),
            "trial": next(i for i in read(prior)["runs"] if i["run"] == target["run"]),
        },
    },
    "decision": {
        "newScheduleAB": "NOT_RUN",
        "rationale": "No measurable pre-/post-decode queue wait capable of removing the 2.528s. The sampled whole-process CPU/load is insufficient to justify raising worker QoS. Heavier competitor CPU consumption in B-9-5 coincides with a shorter exact first EOS than B-9-2; two readings are not causal. Advancing the previous 29.4s preview omits the last 0.68s of this segment. Keep current process priority and exact EOS. The evidence does not prove that optimizing the decoding algorithm is impossible.",
        "productEdits": False,
        "newInstallation": False,
    },
    "inputsSHA256": {
        str(f.relative_to(repo)): digest(f)
        for f in (
            raw_path,
            summary_path,
            clip_path,
            scorer_path,
            history_path,
            draft_path,
            prior,
            repo / "native/LocalASR/Sources/SaytileModelWorker/Worker.swift",
            repo / "Sources/SaytileKit/LocalASRProvider.swift",
            repo / "scripts/mandarin/measure-preview-cost.py",
        )
    },
}
print(json.dumps(report, ensure_ascii=False, indent=2))
