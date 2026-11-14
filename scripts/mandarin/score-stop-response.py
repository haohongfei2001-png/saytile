"""Keep replay completion separate from observed end-of-speech response.

The existing cadence scorer's pipelineSettledAt follows whole-file replay.
Trailing silence may continue after the final text is already visible. Reuse
its unchanged acoustic endpoint estimate and report raw final events and final
text display separately. Displaying the eventual final text is not confirmation:
the provisional text can already equal the final text before a final event.
No word-aligned human speech endpoint or VAD-end event is present in old probes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import runpy

quant = runpy.run_path(str(Path(__file__).resolve().parents[1] / "score-local-asr.py"))["quant"]


def observed_response(receipt, acoustic_end):
    final_text = "".join(reversed(receipt["archive"]))
    frames = receipt["frames"]
    events = receipt["rawWorkerEvents"]
    if not frames or not final_text or frames[-1]["text"] != final_text:
        raise ValueError("The last native frame must equal the nonempty final archive")
    for entries in (frames, events):
        if any(a["t"] > b["t"] for a, b in zip(entries, entries[1:])):
            raise ValueError("Native observations must remain in timestamp order")
    final_events = [event["t"] for event in events if event["kind"] == "final"]
    if not final_events:
        raise ValueError("No observed ASR final event; do not substitute EOF")
    # Walk backward so a matching provisional text that was subsequently changed
    # does not count as the eventual text remaining visible through the run's end.
    final_frame = len(frames) - 1
    while final_frame and frames[final_frame - 1]["text"] == final_text:
        final_frame -= 1
    visible_at = frames[final_frame]["t"]
    raw_final_at = max(final_events)
    return {
        "last_acoustic_signal_estimate_s": acoustic_end,
        "last_raw_final_event_at_s": raw_final_at,
        "eventual_final_text_continuously_visible_from_s": visible_at,
        "raw_final_after_last_acoustic_signal_s": round(raw_final_at - acoustic_end, 3),
        "eventual_final_text_display_after_last_acoustic_signal_s": round(visible_at - acoustic_end, 3),
        "eventual_final_text_display_before_raw_final_s": round(raw_final_at - visible_at, 3),
        "vad_endpoint_status": "NOT_RECORDED",
        "archive_commit_timestamp_status": "NOT_RECORDED",
    }


def measure(cadence_path, receipts):
    cadence = json.loads(cadence_path.read_text())
    rows, identifiers = [], set()
    for source in cadence["rows"]:
        if source["id"] in identifiers:
            raise ValueError("Duplicate clip in cadence report")
        identifiers.add(source["id"])
        path = receipts / ("auto-qwen-small-" + source["id"] + ".json")
        receipt = json.loads(path.read_text())
        if (receipt["sha"] != cadence["source"] or receipt["audio_sha256"] != source["sha256"]
                or receipt["exit_code"] != 0 or not receipt["automatic"]
                or receipt["providers"] != ["qwen-small"]
                or not receipt["recordStates"]
                or any(state != "completed" for state in receipt["recordStates"])):
            raise ValueError("Source, audio, routing, or completion evidence mismatch")
        rows.append({
            "id": source["id"], "receipt_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "audio_sha256": source["sha256"], **observed_response(receipt, source["end"]),
            # Preserve existing numbers exactly; do not silently replace them.
            "whole_file_settled_after_last_acoustic_signal_s": source["after_last_signal_s"],
            "whole_file_settled_after_eof_s": source["after_file_s"],
        })
    metrics = ["raw_final_after_last_acoustic_signal_s",
               "eventual_final_text_display_after_last_acoustic_signal_s",
               "whole_file_settled_after_last_acoustic_signal_s", "whole_file_settled_after_eof_s"]
    return {
        "source": cadence["source"], "clips": len(rows),
        "measurement": ("Same acoustic estimate as existing cadence scorer; eventual final-text display "
                        "can precede ASR confirmation. Neither is a human endpoint or archive commit timestamp."),
        "cadence_sha256": hashlib.sha256(cadence_path.read_bytes()).hexdigest(),
        "summary": {metric: quant([row[metric] for row in rows]) for metric in metrics}, "rows": rows,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("cadence", "receipts", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    args.out.write_text(json.dumps(measure(args.cadence, args.receipts), ensure_ascii=False, indent=2) + "\n")
