#!/usr/bin/env python3
"""Export the disposable native probe's shared-uptime events, without rescoring text.

Decoder wall time includes GPU execution, allocation and host waits. A stage
duration includes its awaited work. These are not CPU-time measurements.
"""
import argparse
import csv
import gzip
import io
import json
import math
from pathlib import Path


def load(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == ".gz" else data)


def describe(values):
    values = sorted(values)
    if not values:
        return None
    return dict(count=len(values), p50_s=values[math.ceil(len(values) * .5) - 1],
                p95_s=values[math.ceil(len(values) * .95) - 1], maximum_s=values[-1])


def summarize(receipt, destination):
    d = load(receipt)
    origin = d["clockOriginUptime"]
    stages = d["stages"]
    assert stages and len(stages) < 50_000, "Absent or truncated trace cannot establish a complete pipeline"
    assert all(a["uptime"] <= b["uptime"] for a, b in zip(stages, stages[1:])), "Unordered trace"
    rows, durations = [], {}
    for e in stages:
        end = e["uptime"] - origin
        duration = e.get("duration", 0)
        rows.append([end - duration, end, e["stage"], e.get("recordingID", ""),
                     e.get("frames", ""), e.get("decision", "")])
        if "duration" in e:
            durations.setdefault(e["stage"], []).append(duration)
    raw = [e for e in d["rawWorkerEvents"] if e["kind"] != "ready"]
    received = [e for e in stages if e["stage"] == "asr.rawReceived"]
    assert len(raw) == len(received)
    queue_delays = []
    for event, receive in zip(raw, received):
        assert event["frames"] == receive["frames"] and event["kind"] == receive["decision"]
        rid = receive["recordingID"]
        rows.append([event["t"], event["t"], "worker.outputObserved", rid, event["frames"], event["kind"]])
        for decode in event.get("decodes") or []:
            start, end = decode["startUptime"], decode["endUptime"]
            rows.append([start - origin, end - origin, "worker.decode", rid,
                         decode["frames"], "final" if decode["final"] else "preview"])
            # The pipe receipt is after write(), so this is a lower bound on
            # helper-side waiting since PCM availability, not microphone delay.
            available = next((e for e in stages if e["stage"] == "asr.pipeWritten"
                              and e["recordingID"] == rid and e["frames"] >= decode["frames"]), None)
            if available:
                queue_delays.append(max(0, start - available["uptime"]))
            durations.setdefault("worker.finalDecode" if decode["final"] else "worker.previewDecode", []).append(end - start)
    for key, stage in [("publications", "ui.timelineTextChanged"), ("frames", "ui.laidOutTextObserved")]:
        for event in d[key]:
            rows.append([event["t"], event["t"], stage, "", "", ""])
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["start_s", "end_s", "stage", "recording_id", "pcm_frames", "decision"])
    writer.writerows(sorted(rows))
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "timeline.csv.gz").write_bytes(gzip.compress(output.getvalue().encode(), mtime=0))
    result = dict(source=d["sha"], origin_uptime=origin, input_sha256=d["audio_sha256"],
                  stages={k: describe(v) for k, v in durations.items()},
                  helper_queue_lower_bound=describe(queue_delays),
                  withheld=sum(e.get("decision") == "withheld" for e in stages),
                  trace_events=len(stages), clock="ProcessInfo.systemUptime, shared across owned processes",
                  physical_microphone="NOT_RUN", view_observation_resolution_s=.035)
    (destination / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    summarize(args.receipt, args.destination)
