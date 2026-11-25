"""Read-only independent follow-up scoring; original32 and soak retain separate scopes."""
import argparse
import collections
import hashlib
import io
import json
from pathlib import Path
import re
import runpy
import tempfile
import wave

REPO = Path(__file__).resolve().parents[3]
CORE = runpy.run_path(str(REPO / "scripts/score-local-asr.py"))
CADENCE = runpy.run_path(str(REPO / "scripts/mandarin/score-live-cadence.py"))
REVERSE = runpy.run_path(str(REPO / "scripts/mandarin/score-preview-reversals.py"))["reversals"]
SHAS = {"baseline": "42d8e98eaf04a56d34a36cc1aca2aff7061150f4",
        "candidate": "73ad857442964437929819ba9965f6bcfdcefd27"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("root", "manifest", "audio", "out"):
        parser.add_argument("--" + key, type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists(), "Preserve the prior report"
    files = {}

    def read(path):
        raw = path.read_bytes()
        files[str(path)] = hashlib.sha256(raw).hexdigest()
        return json.loads(raw)

    manifest = read(args.manifest)
    refs = {r["id"]: r for r in manifest["samples"]}
    report = {"scope": "Three serial AB/BA/AB public-PCM pairs for each original outlier; not a replacement for original32. No microphone or independent hardware test.", "followups": {}}
    for group, ident in (("startup-followup", "ascend-mixed-7c8bdcb41bb98a40"),
                         ("long-tail-followup", "continuous-public-5")):
        progress = read(args.root / group / "progress.json")
        expected = [(1, "baseline"), (1, "candidate"), (2, "candidate"),
                    (2, "baseline"), (3, "baseline"), (3, "candidate")]
        assert [(p["pair"], p["arm"]) for p in progress] == expected
        assert all(p["status"] == "PASS" for p in progress)
        pairs = []
        with tempfile.TemporaryDirectory(prefix="saytile-followup-report-") as temp:
            one_manifest = Path(temp) / "manifest.json"
            one_manifest.write_text(json.dumps({"samples": [refs[ident]]}))
            for pair in (1, 2, 3):
                arms = {}
                for label in ("baseline", "candidate"):
                    folder = args.root / group / f"pair-{pair}" / label
                    raw = read(folder / "visible-raw.json")
                    inv = read(folder / "invocation.json")
                    proc = read(folder / "process.json")
                    samples = read(folder / "process-samples.json")
                    merged = read(folder / f"auto-qwen-small-{ident}.json")
                    assert all(merged[k] == value for k, value in raw.items())
                    assert raw["sha"] == inv["source"] == proc["source"] == SHAS[label]
                    assert inv["exit_code"] == merged["exit_code"] == 0
                    assert raw["automatic"] is True and proc["automatic"] is True
                    assert raw["providers"] == ["qwen-small"] and proc["model"] == "qwen-small"
                    assert inv["sample"] == proc["sample"] == merged["id"] == ident
                    assert inv["audio_sha256"] == proc["audio_sha256"] == merged["audio_sha256"] == refs[ident]["audio_sha256"]
                    measured = CADENCE["measure"](one_manifest, args.audio, folder, SHAS[label], automatic=True)["rows"][0]
                    archive = "".join(reversed(raw["archive"]))
                    words = CADENCE["bigrams"](refs[ident]["reference"])
                    first = next((f["t"] - measured["onset"] for f in raw["frames"]
                                  if f["t"] >= measured["onset"] and words.intersection(CADENCE["bigrams"](f["text"]))), None)
                    cpu = max(s["app_cpu_s"] or 0 for s in samples) + max(s["workers_cpu_s"] for s in samples)
                    footprint = max(sum(s["footprint"].values()) for s in samples) / 2**20
                    arms[label] = {"source": SHAS[label], "build": inv["build"], "first_visible_reference_s": first,
                        "display_first_while_speaking_s": measured["display"]["first_s"],
                        "display_max_effective_gap_s": measured["display"]["longest_s"],
                        "display_gap_position": measured["display"]["longest_position"],
                        "worker_max_effective_gap_s": measured["worker"]["longest_s"],
                        "eos_to_pipeline_settled_s": measured["after_file_s"], "cpu_s": cpu,
                        "peak_simultaneous_footprint_MiB": footprint,
                        "resource_summary_agrees": abs(cpu - proc["combined_cpu_s"]) < .011 and abs(footprint - proc["peak_simultaneous_footprint_MiB"]) < .051,
                        "final_text": archive, "states": raw["recordStates"], "recording_errors": raw["recordingErrors"],
                        "final_visible_matches_archive": measured["matches_final_window"],
                        "surface_blockers": dict(collections.Counter(s["blocker"] for s in raw.get("surfaceStates", []) if s.get("blocker"))),
                        "aba": len(REVERSE(raw["publications"], raw["endOfFile"])), "measured": measured}
                b, c = arms["baseline"], arms["candidate"]
                pairs.append({"pair": pair, "order": [p["arm"] for p in progress if p["pair"] == pair],
                    "arms": arms, "final_text_equal": b["final_text"] == c["final_text"], "states_equal": b["states"] == c["states"],
                    "candidate_minus_baseline": {key: c[key] - b[key] for key in ("first_visible_reference_s", "display_max_effective_gap_s", "eos_to_pipeline_settled_s", "cpu_s", "peak_simultaneous_footprint_MiB")}})
        report["followups"][group] = {"sample": ident, "pairs": pairs}

    original = read(args.root / "regression-final/native-comparison-including-failure.json")
    report["original32_not_replaced"] = {k: {"source": value["source"],
        "normal15": {key: val for key, val in value["normal15"].items() if key != "first_any_rows"},
        "long_clip": value["original_cadence"]["rows"][-1], "surface": value["surface"],
        "failed_invocations": value["failed_invocations"]} for k, value in original["routes"].items()}

    soak = read(args.root / "regression-final/soak.json")
    assert soak["source"] == soak["observed_window_source"] == SHAS["candidate"]
    assert soak["requested_automatic"] is True and soak["observed_automatic"] is True
    assert soak["providers"] == ["qwen-small"] and soak["exit_code"] == 0
    # Reconstruct only the generated public fixture in memory; no playback or ASR.
    pcm_frames, generated_ids, idle = 0, [], None
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        while pcm_frames < 900 * 16000:
            ref = manifest["samples"][len(generated_ids) % len(manifest["samples"])]
            raw = (args.audio / (ref["id"] + ".wav")).read_bytes()
            assert hashlib.sha256(raw).hexdigest() == ref["audio_sha256"]
            with wave.open(io.BytesIO(raw)) as wav:
                assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, 16000)
                pcm = wav.readframes(wav.getnframes())
            output.writeframes(pcm + bytes(32000))
            pcm_frames += len(pcm) // 2 + 16000
            generated_ids.append(ref["id"])
            if idle is None and pcm_frames >= 480 * 16000:
                idle = [pcm_frames / 16000, pcm_frames / 16000 + 45]
                output.writeframes(bytes(2 * 45 * 16000))
                pcm_frames += 45 * 16000
    assert hashlib.sha256(buffer.getvalue()).hexdigest() == soak["fixture_sha256"]
    assert pcm_frames / 16000 == soak["input_duration"] and generated_ids == soak["input_clips"]
    assert idle == soak["idle"]["input_range_seconds"]
    coverage = []
    for entry in soak["clips"]:
        with wave.open(str(args.audio / (entry["id"] + ".wav"))) as wav:
            frames = wav.getnframes()
        coverage.append({**entry, "input_frames": frames, "archived_fraction_of_clip": entry["archive_frames"] / frames})
    report["soak"] = {"receipt": soak, "fixture_reconstruction_sha_verified": True,
        "public_clip_count": len(generated_ids), "distinct_public_clips": len(set(generated_ids)), "clip_coverage": coverage,
        "boundaries": ["The 904.830375 s fixture includes 72 one-second separators and 45 s inserted silence, not 15 min uninterrupted speech.",
            "Stored PCM hashes and timeline associations were checked in the original process. The successful temporary archive was removed; this audit can recheck fixture SHA and retained receipt but not reopen its original SQLite/WAVs.",
            "Every supplied clip has some completed-record audio coverage; the assertion is >0 frames, not complete voiced-frame recall or CER.",
            "2135 display changes were counted, but only the first 512 text frames were retained. This does not establish a maximum display gap throughout the run.",
            "Resources are five-second ps samples: separate process median CPU and RSS, not simultaneous footprint, GPU/ANE, power, or system memory pressure.",
            "Two late-idle process observations are absent and a child later reappears. Raw full sampling trace and process-to-probe clock offset are not retained, so precise release/restart latency is not established.",
            "Automatic route and persistence are exercised; microphone, sleep/wake, abrupt power loss, foreground browser resolver and 8 GB hardware are not."]}

    binding = read(args.root / "qwen-input-audio/binding.json")
    log_path = args.root / "qwen-input-audio/input-audio.log"
    log = log_path.read_text()
    files[str(log_path)] = hashlib.sha256(log_path.read_bytes()).hexdigest()
    match = re.search(r"QWEN_NATIVE_AUDIO_PASS early_writes=(\d+) first_write_s=([0-9.]+) audio_s=([0-9.]+) records=(\d+)", log)
    assert binding["status"] == "PASS" and binding["product_source"] == SHAS["candidate"] and match
    assert binding["input_sha256"] == refs["continuous-public-5"]["audio_sha256"]
    assert "PASS live Qwen final matches archive and preserves surrounding text" in log
    assert "PASS real native fixture never sends" in log
    report["live_qwen_to_owned_AX"] = {"binding": binding, "early_confirmed_writes": int(match[1]),
        "first_confirmed_write_s": float(match[2]), "audio_s": float(match[3]), "records": int(match[4]),
        "scope": "Real Qwen + production coordinator + real background AppKit AX, but target selection injected. Not foreground browser or microphone acceptance. First confirmed write is not first panel preview.",
        "log_otherIntact_false": "No alternate window is created in the background fixture; the optional alternateText nil comparison is false, not an observed overwrite."}
    report["post_regression_events"] = read(args.root / "post-regression.json")
    for path, sha in files.items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == sha, f"changed input: {path}"
    report["input_sha256"] = files
    with args.out.open("x") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write("\n")
    print(json.dumps({group: [{"pair": p["pair"], "equal": p["final_text_equal"],
        "arms": {a: {k: v for k, v in m.items() if k not in ("measured", "final_text")} for a, m in p["arms"].items()}}
        for p in value["pairs"]] for group, value in report["followups"].items()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
