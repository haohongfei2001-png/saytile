"""Isolated paced run with the existing 102-utterance archive audit."""

import sqlite3
import argparse, hashlib, json, pathlib, subprocess, tempfile, time, wave

P = pathlib.Path
p = argparse.ArgumentParser()
for name in ("app", "weights", "fixture", "output"):
    p.add_argument("--" + name, type=P, required=True)
p.add_argument("--model", choices=("zipformer", "qwen-small"), required=True)
a = p.parse_args()
exe = a.app / "Contents/MacOS/Saytile"
with tempfile.TemporaryDirectory(prefix="saytile-local-final-soak.", dir="/tmp") as raw:
    root = P(raw)
    (root / "LocalModels").mkdir()
    subprocess.run(["cp", "-cR", a.weights / a.model, root / "LocalModels"], check=True)
    with wave.open(str(a.fixture)) as w:
        assert (
            w.getframerate() == 16000
            and w.getnchannels() == 1
            and w.getsampwidth() == 2
        )
        audio = w.readframes(w.getnframes())
    with wave.open(str(root / "fixture.wav"), "wb") as w:
        w.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        for i in range(102):
            w.writeframes(audio + bytes(32000))
    sha = hashlib.file_digest((root / "fixture.wav").open("rb"), "sha256").hexdigest()
    assert sha == "5a431ac247e1f7f4d8334d03f2bfdd3650d86e8fb961e916967fe6018b6d1696"
    start = time.monotonic()
    with subprocess.Popen(
        [exe, "--data-directory", root, "--local-stream-probe", a.model],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ) as proc:
        with (root / "samples").open("w") as samples:
            while proc.poll() is None:
                if time.monotonic() - start > 1990:
                    proc.terminate()
                    raise RuntimeError("soak deadline")
                pids = [str(proc.pid)] + subprocess.run(
                    ["pgrep", "-P", str(proc.pid)], capture_output=True, text=True
                ).stdout.split()
                assert len(pids) <= 2
                for pid in pids:
                    values = subprocess.run(
                        ["ps", "-p", pid, "-o", "rss=,pcpu="],
                        capture_output=True,
                        text=True,
                    ).stdout.split()
                    if len(values) == 2:
                        samples.write(
                            " ".join(
                                [pid, str(round(time.monotonic() - start, 2))] + values
                            )
                            + "\n"
                        )
                samples.flush()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    pass
        view = (
            json.loads((root / "visible.json").read_text())
            if (root / "visible.json").exists()
            else {}
        )
        db = sqlite3.connect((root / "Saytile.sqlite").as_uri() + "?mode=ro", uri=True)
        diagnostic = dict(
            model=a.model,
            source=view.get("sha"),
            probe_exit=proc.returncode,
            paced_seconds=view.get("endOfFile"),
            displayed_changes=view.get("displayedChanges"),
            record_states=db.execute(
                "select recognition_state,audio_state,count(*) from recordings group by 1,2"
            ).fetchall(),
            errors=db.execute(
                "select last_error,count(*) from recordings where last_error is not null group by 1"
            ).fetchall(),
        )
        a.output.with_suffix(".counts.json").write_text(
            json.dumps(diagnostic, ensure_ascii=False, indent=2) + "\n"
        )
        assert proc.returncode == 0, proc.returncode
    subprocess.run(
        [
            "python3",
            "scripts/inspect-local-soak.py",
            "--model",
            a.model,
            "--root",
            root,
            "--samples",
            root / "samples",
            "--output",
            a.output,
        ],
        check=True,
    )
