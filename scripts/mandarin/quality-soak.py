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
    with wave.open(str(fixture), "wb") as output:
        output.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        while frames < 15 * 60 * 16000:
            row = rows[len(inputs) % len(rows)]
            path = args.wav / (row["id"] + ".wav")
            assert hashlib.sha256(path.read_bytes()).hexdigest() == row["audio_sha256"]
            with wave.open(str(path)) as recording:
                assert (recording.getnchannels(), recording.getsampwidth(), recording.getframerate()) == (1, 2, 16000)
                pcm = recording.readframes(recording.getnframes())
            output.writeframes(pcm + bytes(32000))
            frames += len(pcm) // 2 + 16000
            inputs.append(row["id"])
    samples = collections.defaultdict(list)
    start = time.monotonic()
    with subprocess.Popen([args.app / "Contents/MacOS/Saytile", "--data-directory", root,
                           "--local-stream-probe", args.model], stdout=subprocess.DEVNULL) as proc:
        try:
            while proc.poll() is None:
                if time.monotonic() - start > frames / 16000 + 180:
                    raise TimeoutError("Recognition did not settle after the input ended")
                children = subprocess.run(["pgrep", "-P", str(proc.pid)], capture_output=True, text=True).stdout.split()
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
        paths = db.execute("select path,frames from chunks order by path").fetchall()
        archive_frames = q("select sum(total_frames) from recordings")
        dispatches = q("select count(*) from dispatches")
    recovered = 0
    hashes = hashlib.sha256()
    for paragraph, count in paths:
        audio = root / "Audio" / paragraph
        assert not audio.is_symlink() and (root / "Audio").resolve() in audio.resolve().parents
        with wave.open(str(audio)) as w:
            assert w.getnframes() == count
            data = w.readframes(count)
            assert len(data) == 2 * count
            hashes.update(hashlib.sha256(data).digest())
            recovered += count
    report = dict(model=args.model, source=metadata["SaytileSourceRevision"], observed_window_source=view.get("sha"), errors=errors, fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),
                  input_clips=inputs, input_duration=frames / 16000, elapsed=view.get("endOfFile"), exit_code=proc.returncode,
                  ui_updates=view.get("displayedChanges", 0), retained_ui_frames=len(view.get("frames", [])), providers=[row[0] for row in engines],
                  archived_seconds=recovered / 16000, archive_chunks=len(paths), states=states, completed_rows=rows_ready,
                  total_rows=rows_total, integrity=integrity, foreign_errors=len(foreign), dispatches=dispatches,
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
    report["passed"] = (proc.returncode == 0 and view.get("sha") == metadata["SaytileSourceRevision"]
                        and view.get("endOfFile", 0) >= 900 and report["providers"] == [provider]
                        and integrity == "ok" and not foreign and dispatches == 0 and recovered == archive_frames
                        and rows_ready == rows_total and rows_ready > 0 and report["ui_updates"] >= 2)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if not report["passed"]:
        raise SystemExit("native soak failed; see the machine receipt")
