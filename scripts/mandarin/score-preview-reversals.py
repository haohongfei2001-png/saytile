#!/usr/bin/env python3
"""Find short localized A→B→A reversals in native or replayed ASR previews.

Pass receipt files/directories from isolated public-audio runs. The default
uses actual issued publications and the clip's EOF. --replay supplies the same
receipts after a common gate (JSON object keyed by the supplied receipt paths).
"""
import argparse
from collections import Counter
from difflib import SequenceMatcher
import hashlib
import json
from pathlib import Path
import runpy

normalize = runpy.run_path(str(Path(__file__).resolve().parents[1] / "score-local-asr.py"))["norm"]


def reversals(events, end):
    snapshots = [(e["t"], normalize(e["text"]), e.get("kind")) for e in events
                 if e["text"] and e.get("kind") != "ready"]
    found = []
    for index in range(1, len(snapshots) - 1):
        _, before, previous_kind = snapshots[index - 1]
        at, middle, kind = snapshots[index]
        if at >= end or kind == "final" or previous_kind == "final" or not middle or middle.startswith(before):
            continue
        changes = [item for item in SequenceMatcher(None, before, middle, autojunk=False).get_opcodes()
                   if item[0] != "equal"]
        # Count each fluctuating snapshot once, using the first anchored edit
        # recovered in either of the next two observations. Never cross EOS.
        for offset, (returned_at, after, future_kind) in enumerate(snapshots[index + 1:index + 3], 1):
            for _, left, right, new_left, new_right in changes:
                old = before[left:right]
                new = middle[new_left:new_right]
                if left >= len(before) or max(len(old), len(new)) > 4:
                    continue
                left_context = middle[max(0, new_left - 3):new_left]
                right_context = middle[new_right:new_right + 3]
                if len(left_context) + len(right_context) < 3:
                    continue
                old_anchor = middle[:new_left] + old + right_context
                new_anchor = middle[:new_right] + right_context
                if after.startswith(old_anchor) and not after.startswith(new_anchor):
                    pure = len(middle) <= len(before) and all(
                        a < len(before) and b - a <= 4 and d - c <= 4 for _, a, b, c, d in changes)
                    found.append({"t": round(at, 4), "return_t": round(returned_at, 4), "observations": offset,
                                  "old": old, "transient": new, "no_new_tail": pure})
                    break
            else:
                if future_kind == "final":
                    break
                continue
            break
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipts", type=Path, nargs="*")
    parser.add_argument("--replay", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    replay = json.loads(args.replay.read_text()) if args.replay else {}
    files = set(Path(k) for k in replay)
    for path in args.receipts:
        files.update(path.rglob("auto-*.json") if path.is_dir() else [path])
    if not files:
        parser.error("provide native receipts or a gate replay")
    rows = []
    totals = Counter()
    for path in sorted(files):
        contents = path.read_bytes()
        data = json.loads(contents)
        events = replay[str(path)] if args.replay else data["publications"]
        matches = reversals(events, data["endOfFile"])
        rows.append({"id": data["id"], "source": data["sha"], "wav_sha256": data["audio_sha256"],
                     "receipt_sha256": hashlib.sha256(contents).hexdigest(), "count": len(matches),
                     "observations": matches})
        totals.update(receipts=1, reversals=len(matches), next_observation=sum(m["observations"] == 1 for m in matches),
                      second_observation=sum(m["observations"] == 2 for m in matches),
                      no_new_tail=sum(m["no_new_tail"] for m in matches))
    result = {"layer": "common_gate_replay" if args.replay else "issued_publications",
              "window": "before endOfFile; up to two subsequent observed hypotheses, including final",
              "summary": totals, "receipts": rows}
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
