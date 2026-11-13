"""Wall-paced native use on a fixed sequence of licensed clips, with an isolated SQLite archive."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import sqlite3
import statistics
import subprocess
import tempfile
import time
import wave

parser = argparse.ArgumentParser(description=__doc__)
for name in ("app", "weights", "wav", "manifest", "output"):
    parser.add_argument("--" + name, type=Path, required=True)
parser.add_argument("--model", choices=("apple", "sherpa", "qwen-small", "qwen-large"), required=True)
parser.add_argument("--automatic", action="store_true", help="Use the app's production default, with --model as the expected engine")
args = parser.parse_args()
rows = json.loads(args.manifest.read_text())["samples"]
assert rows and not args.output.exists()
metadata = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
provider = "apple-speech-analyzer" if args.model == "apple" else args.model
with tempfile.TemporaryDirectory(prefix="saytile-mandarin-quality-soak-") as tmp:
    root = Path(tmp)
    fixture = root / "fixture.wav"
    if args.model != "apple":
        (root / "LocalModels").mkdir()
        subprocess.run(["cp", "-cR", args.weights / args.model, root / "LocalModels"], check=True)
    frames = 0
    inputs = []
    input_ranges = []
    # Pause partway through so the normal idle timer can release the helper.
    # A following clip verifies that recognition resumes.
    idle_window = None
    with wave.open(str(fixture), "wb") as output:
        output.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        while frames < 15 * 60 * 16000:
            row = rows[len(inputs) % len(rows)]
            path = args.wav / (row["id"] + ".wav")
            assert hashlib.sha256(path.read_bytes()).hexdigest() == row["audio_sha256"]
            with wave.open(str(path)) as recording:
                assert (recording.getnchannels(), recording.getsampwidth(), recording.getframerate()) == (1, 2, 16000)
                pcm = recording.readframes(recording.getnframes())
            input_ranges.append((frames, frames + len(pcm) // 2))
            output.writeframes(pcm + bytes(32000))
            frames += len(pcm) // 2 + 16000
            inputs.append(row["id"])
            if idle_window is None and frames >= 8 * 60 * 16000:
                start_frame = frames
                output.writeframes(bytes(2 * 45 * 16000))
                frames += 45 * 16000
                idle_window = (start_frame / 16000, frames / 16000)
    samples = collections.defaultdict(list)
    worker_presence = []
    start = time.monotonic()
    with subprocess.Popen([args.app / "Contents/MacOS/Saytile", "--data-directory", root,
                           "--local-stream-probe", "auto" if args.automatic else args.model], stdout=subprocess.DEVNULL) as proc:
        try:
            while proc.poll() is None:
                if time.monotonic() - start > frames / 16000 + 180:
                    raise TimeoutError("Recognition did not settle after the input ended")
                children = subprocess.run(["pgrep", "-P", str(proc.pid)], capture_output=True, text=True).stdout.split()
                worker_presence.append((time.monotonic() - start, bool(children)))
                for kind, pids in (("app", [str(proc.pid)]), ("worker", children)):
                    rss = cpu = 0
                    for pid in pids:
                        values = subprocess.run(["ps", "-p", pid, "-o", "rss=,pcpu="], capture_output=True, text=True).stdout.split()
                        if len(values) == 2:
                            rss += int(values[0])
                            cpu += float(values[1])
                    if rss:
                        samples[kind].append([time.monotonic() - start, rss / 1024, cpu])
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=12)
    view_file = root / "visible.json"
    view = json.loads(view_file.read_text()) if view_file.is_file() else {}
    with sqlite3.connect((root / "Saytile.sqlite").as_uri() + "?mode=ro", uri=True) as db:
        integrity = db.execute("pragma integrity_check").fetchone()[0]
        foreign = db.execute("pragma foreign_key_check").fetchall()
        q = lambda sql: db.execute(sql).fetchone()[0]
        states = db.execute("select recognition_state,audio_state,count(*) from recordings group by 1,2").fetchall()
        errors = db.execute("select last_error,count(*) from recordings where last_error is not null group by last_error").fetchall()
        engines = db.execute("select distinct json_extract(payload,'$.provider') from model_runs order by 1").fetchall()
        rows_ready = q("select count(*) from recordings r join revisions v on v.id=r.preferred_revision where r.audio_state='available' and r.recognition_state='completed' and r.is_recording=0 and length(v.text)>0")
        rows_total = q("select count(*) from recordings")
        timeline_rows = q("select count(*) from transcript_timeline")
        paths = db.execute("""select c.path,c.frames,t.position,r.recognition_state
            from chunks c join transcript_timeline t on t.recording_id=c.recording_id
            join recordings r on r.id=c.recording_id order by t.position,c.ordinal""").fetchall()
        archive_frames = q("select sum(total_frames) from recordings")
        dispatches = q("select count(*) from dispatches")
    recovered = 0
    hashes = hashlib.sha256()
    with wave.open(str(fixture)) as source:
        input_pcm = source.readframes(source.getnframes())
    cursor = 0
    ranges = []
    unmatched = []
    for index, (paragraph, count, position, recognition_state) in enumerate(paths):
        audio = root / "Audio" / paragraph
        assert not audio.is_symlink() and (root / "Audio").resolve() in audio.resolve().parents
        with wave.open(str(audio)) as w:
            assert (w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()) == (count, 1, 2, 16000)
            data = w.readframes(count)
            assert len(data) == 2 * count
            hashes.update(hashlib.sha256(data).digest())
            recovered += count
            if data:
                offset = input_pcm.find(data, cursor)
                if offset < 0 or offset % 2:
                    unmatched.append(index)
                else:
                    cursor = offset + len(data)
                    ranges.append((offset // 2, cursor // 2, position, recognition_state))
    # VAD deliberately omits quiet periods. Match each stored chunk against
    # the input PCM, in time order, then check every supplied clip has audio
    # belonging to a record with a completed transcript.
    clip_evidence = []
    for clip, (start_frame, end_frame) in zip(inputs, input_ranges, strict=True):
        overlaps = [(min(hi, end_frame) - max(lo, start_frame), position, state)
                    for lo, hi, position, state in ranges if lo < end_frame and hi > start_frame]
        clip_evidence.append(dict(id=clip, archive_frames=sum(n for n, _, _ in overlaps),
                                  completed_frames=sum(n for n, _, state in overlaps if state == "completed"),
                                  positions=sorted({position for _, position, _ in overlaps})))
    report = dict(model=args.model, requested_automatic=args.automatic, observed_automatic=view.get("automatic"), source=metadata["SaytileSourceRevision"], observed_window_source=view.get("sha"), errors=errors, fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),
                  input_clips=inputs, input_duration=frames / 16000, elapsed=view.get("endOfFile"), exit_code=proc.returncode,
                  ui_updates=view.get("displayedChanges", 0), retained_ui_frames=len(view.get("frames", [])), providers=[row[0] for row in engines],
                  archived_seconds=recovered / 16000, archive_chunks=len(paths), states=states, completed_rows=rows_ready,
                  total_rows=rows_total, integrity=integrity, foreign_errors=len(foreign), dispatches=dispatches,
                  timeline_rows=timeline_rows, unmatched_chunk_ordinals=unmatched, clips=clip_evidence,
                  readable_pcm_manifest=hashes.hexdigest(), resources={})
    # Aggregate only sampled periods. An early exit leaves the final window unavailable.
    for label, observations in samples.items():
        early = [item[1] for item in observations if item[0] <= 300]
        late = [item[1] for item in observations if item[0] > frames / 16000 - 300]
        report["resources"][label] = dict(samples=len(observations),
            median_cpu_percent=round(statistics.median(item[2] for item in observations), 2),
            peak_RSS_MiB=round(max(item[1] for item in observations), 2),
            first_5min_median_RSS_MiB=round(statistics.median(early), 2) if early else None,
            last_5min_median_RSS_MiB=round(statistics.median(late), 2) if late else None)
    assert idle_window
    # The final-file receipt yields the actual playback clock including setup.
    playback_start = (view.get("endOfFile") or 0) - frames / 16000
    quiet_start, quiet_end = [x + playback_start for x in idle_window]
    quiet_observations = [(t, present) for t, present in worker_presence if quiet_start + 35 <= t <= quiet_end - 1]
    woke_again = any(present for t, present in worker_presence if t >= quiet_end + 4)
    worker_released = bool(quiet_observations) and all(not v for _, v in quiet_observations)
    report["idle"] = dict(input_range_seconds=idle_window, sampled_after_35_seconds=quiet_observations,
                          released=worker_released, worker_observed_again_after_speech=woke_again)
    helper_ok = args.model == "apple" or worker_released and woke_again
    report["passed"] = (proc.returncode == 0 and view.get("sha") == metadata["SaytileSourceRevision"]
                        and (not args.automatic or view.get("automatic") is True)
                        and view.get("endOfFile", 0) >= 900 and report["providers"] == [provider]
                        and integrity == "ok" and not foreign and dispatches == 0 and recovered == archive_frames
                        and not unmatched and len(list((root / "Audio").rglob("*.wav"))) == len(paths)
                        and timeline_rows == rows_total and all(clip["completed_frames"] > 0 for clip in clip_evidence)
                        and rows_ready == rows_total and rows_ready > 0 and report["ui_updates"] >= 2 and helper_ok)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if not report["passed"]:
        # Preserve only this generated public fixture archive for analysis. The
        # clone excludes the reusable weights and never opens the installed app's data.
        diagnostic = args.output.with_suffix(".failed-archive")
        shutil.copytree(root, diagnostic, ignore=shutil.ignore_patterns("LocalModels"))
        raise SystemExit("native soak failed; see the machine receipt")
