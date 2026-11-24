#!/usr/bin/env python3
"""Score only complete, matched 420+20 wall-paced product cohorts; never infer UI timing."""
import argparse
import collections
import hashlib
import io
import json
import math
from pathlib import Path
import re
import runpy
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
CORE = runpy.run_path(str(ROOT / "scripts/score-local-asr.py"))
SOURCES = {"fleurs": 160, "ascend-zh": 80, "ascend-mixed": 80,
           "aishell1-test": 100, "quiet": 10, "noise15db": 10}
DERIVED = {"quiet", "noise15db"}
RESOURCE_FIELDS = ("cpu_s", "combined_cpu_s", "peak_footprint_MiB", "peak_rss_bytes")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def number(value, name):
    require(type(value) in (int, float) and math.isfinite(value) and value >= 0,
            f"invalid nonnegative finite {name}")
    return value


def snapshot(path, snapshots):
    data = path.read_bytes()
    snapshots[path] = digest(data)
    return data


def read_manifest(path, expected_hash, snapshots):
    data = snapshot(path, snapshots)
    require(digest(data) == expected_hash, "manifest SHA differs from frozen input")
    refs = json.loads(data)
    require(isinstance(refs, list) and len(refs) == 440, "manifest must contain all 440 rows")
    ids = [r["id"] for r in refs]
    require(len(set(ids)) == 440, "duplicate manifest ID")
    require(dict(collections.Counter(r["source"] for r in refs)) == SOURCES,
            "original420/derived20 source counts changed")
    for r in refs:
        require(isinstance(r["id"], str) and re.fullmatch(r"[A-Za-z0-9_-]+", r["id"]), "unsafe audio ID")
        require(isinstance(r["reference"], str) and CORE["norm"](r["reference"]), "empty reference")
        require(re.fullmatch(r"[0-9a-f]{64}", r["audio_sha256"]), "invalid audio SHA")
        number(r["duration"], "manifest duration")
    return refs


def read_arm(path, refs, snapshots):
    data = snapshot(path, snapshots)
    require(data.endswith(b"\n"), f"{path.name}: unfinished JSONL row")
    rows = [json.loads(line) for line in data.splitlines()]
    require(len(rows) == 440, f"{path.name}: incomplete/extra rows ({len(rows)}/440)")
    require([r["id"] for r in rows] == [r["id"] for r in refs],
            f"{path.name}: duplicate, missing, reordered or extra ID")
    for r in rows:
        prefix = f"{path.name}/{r['id']}"
        require((r["model"], r["path"], r["pacing"]) == ("qwen-small", "product", "realtime"),
                f"{prefix}: wrong model, product route or pacing")
        # No provider is an observable product failure, not permission to omit
        # this reference. An unexpected/mixed provider invalidates comparison.
        require(r["providers"] in ([], ["qwen-small"]), f"{prefix}: wrong provider")
        require(isinstance(r["text"], str), f"{prefix}: text is not a string")
        for key in ("states", "errors"):
            require(isinstance(r[key], list) and all(isinstance(v, str) for v in r[key]),
                    f"{prefix}: invalid {key}")
        require(set(r["states"]) <= {"queued", "running", "completed", "failed", "cancelled"},
                f"{prefix}: unknown product state")
        require(type(r["audioFrames"]) is int and r["audioFrames"] > 0, f"{prefix}: invalid frame count")
        for key in ("audioSeconds", "feedSeconds", "maximumFeedLateness", "settledAfterFeedSeconds"):
            number(r[key], f"{prefix}/{key}")
        # Exactly the fixture's declared 1 ms sleep tolerance, not a changed
        # realtime performance threshold. Slow feed is retained and quantified.
        require(r["feedSeconds"] + .001 >= r["audioSeconds"], f"{prefix}: accelerated feed")
    return rows


def check_audio(refs, arms, audio):
    total_frames = total_bytes = 0
    for i, ref in enumerate(refs):
        path = audio / (ref["id"] + ".wav")
        raw = path.read_bytes()
        require(digest(raw) == ref["audio_sha256"], f"{ref['id']}: WAV SHA mismatch")
        with wave.open(io.BytesIO(raw)) as w:
            require((w.getnchannels(), w.getframerate(), w.getsampwidth(), w.getcomptype()) ==
                    (1, 16000, 2, "NONE"), f"{ref['id']}: WAV is not mono 16 kHz PCM16")
            frames = w.getnframes()
            require(len(w.readframes(frames)) == frames * 2, f"{ref['id']}: truncated WAV payload")
        duration = frames / 16000
        require(abs(ref["duration"] - duration) <= 1 / 16000, f"{ref['id']}: manifest duration mismatch")
        for label, rows in arms.items():
            r = rows[i]
            require(r["audioSHA256"] == ref["audio_sha256"] and r["audioFrames"] == frames,
                    f"{label}/{ref['id']}: audio SHA/frame mismatch")
            require(abs(r["audioSeconds"] - duration) < 1e-9, f"{label}/{ref['id']}: audio duration mismatch")
        total_frames += frames
        total_bytes += len(raw)
    return {"files": len(refs), "frames": total_frames, "seconds": total_frames / 16000,
            "wav_bytes": total_bytes, "all_hashes_and_frames_match": True}


def check_build(path, manifest_hash, fixture_hash, snapshots):
    receipt = json.loads(snapshot(path, snapshots))
    require(receipt["input_manifest_sha256"] == manifest_hash, f"{path.name}: manifest binding mismatch")
    require(receipt["fixture_source_sha256"] == fixture_hash, f"{path.name}: fixture source mismatch")
    require(receipt["pacing"] == "realtime" and receipt["original_samples"] == 420 and
            receipt["derived_samples"] == 20, f"{path.name}: route/count mismatch")
    executable = Path(receipt["executable"])
    require(digest(snapshot(executable, snapshots)) == receipt["sha256"], f"{path.name}: executable SHA mismatch")
    return {"receipt": str(path), "receipt_sha256": snapshots[path],
            "executable_sha256": receipt["sha256"], "fixture_source_sha256": fixture_hash,
            "product_source_binding": "NOT_EMBEDDED: attach the separately verified library/build source-equivalence receipt"}


def summarize(refs, rows):
    groups = collections.defaultdict(collections.Counter)
    issues = []
    for ref, r in zip(refs, rows):
        counts = CORE["rating"](ref["reference"], r["text"])
        group = "derived20" if ref["source"] in DERIVED else "original420"
        for key in (ref["source"], group):
            groups[key].update(counts)
            groups[key]["rows"] += 1
        reasons = []
        if not CORE["norm"](r["text"]): reasons.append("empty_final")
        if not r["providers"]: reasons.append("no_model_run")
        if not r["states"]: reasons.append("no_recordings")
        if any(s != "completed" for s in r["states"]): reasons.append("noncompleted_segment")
        if r["errors"]: reasons.append("recorded_error")
        if reasons:
            issues.append({"id": ref["id"], "reasons": reasons, "text": r["text"],
                           "states": r["states"], "errors": r["errors"], "score": counts})
    metrics = {}
    for label, values in (
        ("feed_over_audio_s", [r["feedSeconds"] - r["audioSeconds"] for r in rows]),
        ("maximum_feed_lateness_s", [r["maximumFeedLateness"] for r in rows]),
        ("post_feed_store_settled_s", [r["settledAfterFeedSeconds"] for r in rows]),
    ):
        metrics[label] = {**CORE["quant"](values), "max": max(values), "sum": sum(values)}
    resources = {}
    for field in RESOURCE_FIELDS:
        values = [number(r[field], field) for r in rows if field in r]
        resources[field] = {"status": "RECORDED" if len(values) == 440 else "PARTIAL" if values else "NOT_RECORDED",
                            "rows": len(values), "p50_p95": CORE["quant"](values), "max": max(values) if values else None}
    return {"groups": {k: {"rows": v["rows"], **CORE["pooled"](v)} for k, v in groups.items()},
            "issues": issues, "rows_with_issues": len(issues), "timing": metrics, "resources": resources,
            "first_text_and_update_intervals": "NOT_RECORDED: use the separate complete native AppKit paired16 receipts"}


def compare(refs, arms):
    routes = {label: summarize(refs, rows) for label, rows in arms.items()}
    pairs = []
    for ref, b, c in zip(refs, arms["baseline"], arms["candidate"]):
        before, after = (CORE["rating"](ref["reference"], r["text"]) for r in (b, c))
        pairs.append({"id": ref["id"], "source": ref["source"], "reference": ref["reference"],
                      "text_equal": b["text"] == c["text"], "normalized_equal": CORE["norm"](b["text"]) == CORE["norm"](c["text"]),
                      "state_equal": b["states"] == c["states"], "error_delta": after["errors"] - before["errors"],
                      "baseline": {"text": b["text"], "states": b["states"], "score": before},
                      "candidate": {"text": c["text"], "states": c["states"], "score": after}})
    return {"routes": routes, "pairs": pairs, "comparison": {
        "exact_final_equal": sum(r["text_equal"] for r in pairs),
        "normalized_final_equal": sum(r["normalized_equal"] for r in pairs),
        "state_equal": sum(r["state_equal"] for r in pairs),
        "improved_rows": sum(r["error_delta"] < 0 for r in pairs),
        "regressed_rows": sum(r["error_delta"] > 0 for r in pairs),
        "quality_nonregression": {group: routes["candidate"]["groups"][group]["errors"] <=
                                   routes["baseline"]["groups"][group]["errors"] for group in ("original420", "derived20")}}}


def report(root, manifest, expected_hash, audio, fixture):
    snapshots = {}
    refs = read_manifest(manifest, expected_hash, snapshots)
    progress = json.loads((root / "progress.json").read_bytes())
    latest = {e["arm"]: e for e in progress if e.get("phase") == "quality" and e.get("arm") in ("baseline", "candidate")}
    require(all(latest.get(k, {}).get("status") == "PASS" and latest[k].get("exit_code") == 0
                for k in ("baseline", "candidate")), "both quality processes must finish successfully before scoring")
    arms = {label: read_arm(root / "quality" / (label + "-realtime440.jsonl"), refs, snapshots)
            for label in ("baseline", "candidate")}
    fixture_hash = digest(snapshot(fixture, snapshots))
    builds = {label: check_build(root.parent / "setup" / ("cohort-" + name + ".json"), expected_hash, fixture_hash, snapshots)
              for label, name in (("baseline", "baseline"), ("candidate", "current"))}
    audio_check = check_audio(refs, arms, audio)
    result = compare(refs, arms)
    for path, sha in snapshots.items():
        require(digest(path.read_bytes()) == sha, f"input changed during scoring: {path}")
    return {"validation_status": "PASS", "scope": "Complete fixed 420 originals plus 20 derived public WAVs; product CaptureWorker at wall-clock rate. Not microphone or AppKit visibility acceptance.",
            "scoring": "Existing score-local-asr.py rating/pooled/quant; NFKC/casefold, punctuation spacing, no lexical rewrites. Empty/failed outputs retain every reference unit; original and derived cohorts remain separate.",
            "timing_scope": "Monotonic fixture times. post_feed_store_settled_s also includes final store readback; it is not raw ASR EOS time. Feed lateness is disclosed, never excluded from CER.",
            "release_verdict": "NOT_ASSESSED: complete data validation is not product acceptance",
            "input_sha256": {str(p): sha for p, sha in snapshots.items()}, "builds": builds,
            "audio": audio_check, **result}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root", type=Path, required=True, help="completed regression-final directory")
    p.add_argument("--manifest", type=Path, required=True)
    p.add_argument("--manifest-sha256", required=True, help="frozen before the run, not inferred from results")
    p.add_argument("--audio", type=Path, required=True)
    p.add_argument("--fixture", type=Path, default=ROOT / "tests/fixtures/MandarinCohort.swift")
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    try:
        require(not a.out.exists(), "output already exists; preserve the previous evidence")
        result = report(a.root, a.manifest, a.manifest_sha256, a.audio, a.fixture)
        with a.out.open("x") as f:
            f.write(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    except (OSError, ValueError, KeyError, TypeError, wave.Error) as error:
        print(f"BLOCKED: no comparison written: {error}", file=sys.stderr)
        return 2
    print(json.dumps({"validation_status": result["validation_status"], "comparison": result["comparison"],
                      "groups": {k: r["groups"] for k, r in result["routes"].items()}}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
