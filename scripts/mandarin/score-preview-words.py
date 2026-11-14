"""Score native panel, publication and worker progress on one public cohort.

Build reference-words.swift with swiftc and pass the same binary to every arm.
The first occurrence of a distinct reference word type counts once per layer.
This is a timing signal, not word error rate or an ordered word alignment.
"""
import argparse
import hashlib
import json
from pathlib import Path
import runpy
import subprocess

HERE = Path(__file__).resolve().parent
base = runpy.run_path(str(HERE.parent / "score-local-asr.py"))
norm, quant = base["norm"], base["quant"]
LAYERS = {"window": "frames", "publication": "publications", "worker": "rawWorkerEvents"}


def deltas(events):
    return [b - a for a, b in zip(events, events[1:])]


def analyze(events, start, end, words, reference, visible):
    times = {"literal": [], "lexical": [], "reference_words": []}
    previous, previous_normalized, seen_words = "", "", set()
    for event in events:
        t, text = event["t"], event["text"]
        if not start <= t < end or not text or (visible and not event["speaking"]):
            continue
        normalized = norm(text)
        if previous != text:
            times["literal"].append(t)
        if normalized and normalized != previous_normalized:
            times["lexical"].append(t)
        matched = words[text] & words[reference]
        if matched - seen_words:
            times["reference_words"].append(t)
        seen_words.update(matched)
        previous, previous_normalized = text, normalized
    return times


def run(cadence, manifest, receipts, tokenizer):
    measurement = json.loads(cadence.read_text())
    references = {r["id"]: r for r in json.loads(manifest.read_text())["samples"]}
    checks, texts = [], set()
    for row in measurement["rows"]:
        ident = row["id"]
        raw = json.loads((receipts / ("auto-qwen-small-" + ident + ".json")).read_text())
        ref = references[ident]
        assert ref["audio_sha256"] == raw["audio_sha256"] == row["sha256"]
        assert raw["sha"] == measurement["source"] and raw["exit_code"] == 0
        texts.add(ref["reference"])
        for name in LAYERS.values():
            texts.update(event["text"] for event in raw[name])
        checks.append((row, raw, ref["reference"]))

    inputs = sorted(texts)
    tokenized = json.loads(subprocess.check_output(
        [tokenizer], input=json.dumps(inputs, ensure_ascii=False).encode()
    ))
    assert len(inputs) == len(tokenized)
    words = {text: {norm(token) for token in units if norm(token)} for text, units in zip(inputs, tokenized)}
    rows, pool = [], {}
    for row, raw, reference in checks:
        start, end = row["onset"], row["end"]
        layers = {}
        for layer, field in LAYERS.items():
            timed = analyze(raw[field], start, end, words, reference, layer == "window")
            metrics = {}
            for kind, events in timed.items():
                longest = max(deltas([start, *events, end]))
                first = events[0] - start if events else None
                gaps = deltas(events)
                group = pool.setdefault((layer, kind), {"first": [], "gaps": [], "longest": []})
                if first is not None:
                    group["first"].append(first)
                group["gaps"].extend(gaps)
                group["longest"].append(longest)
                metrics[kind] = {"count": len(events), "first_s": round(first, 3) if first is not None else None,
                                 "internal_gaps_s": quant(gaps), "longest_s": round(longest, 3)}
            layers[layer] = metrics
        rows.append({"id": row["id"], "audio_sha256": row["sha256"], "layers": layers,
                     "final_cer": row["final_CER"], "matches_final_window": row["matches_final_window"],
                     "after_file_s": row["after_file_s"], "after_last_signal_s": row["after_last_signal_s"]})
    summary = {layer + "/" + kind: {"first_s": quant(v["first"]), "internal_gaps_s": quant(v["gaps"]),
                                      "longest_s": round(max(v["longest"]), 3)}
               for (layer, kind), v in pool.items()}
    return {"source": measurement["source"], "tokenizer_sha256": hashlib.sha256(tokenizer.read_bytes()).hexdigest(),
            "summary": summary, "rows": rows}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("cadence", "manifest", "receipts", "tokenizer", "out"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    result = run(args.cadence, args.manifest, args.receipts, args.tokenizer.resolve())
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
