#!/usr/bin/env python3
"""Exercise the shipped archive-recovery command in a new synthetic directory."""
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid
import wave


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(app, *args, success=True):
    result = subprocess.run([app, *map(str, args)], capture_output=True, text=True, timeout=60)
    if (result.returncode == 0) != success:
        raise RuntimeError(result.stdout + result.stderr)
    return result


def add_record(directory, text, start):
    record, revision, chunk = [str(uuid.uuid4()).upper() for _ in range(3)]
    relative = Path(record) / (chunk + ".wav")
    wav = directory / "Audio" / relative
    wav.parent.mkdir()
    with wave.open(str(wav), "wb") as audio:
        audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        audio.writeframes(b"\x02\x02" * 1600)
    with sqlite3.connect(directory / "Saytile.sqlite") as db:
        db.execute("""INSERT INTO recordings(id,created_at,sample_rate,is_recording,audio_state,recognition_state,pinned)
                      VALUES(?,?,16000,0,'available','completed',1)""", (record, start))
        db.execute("INSERT INTO chunks(id,recording_id,path,frames,ordinal) VALUES(?,?,?,1600,0)", (chunk, record, str(relative)))
        db.execute("INSERT INTO revisions(id,recording_id,text,origin,created_at) VALUES(?,?,?,'final',?)",
                   (revision, record, text, start + 1))
        db.execute("UPDATE recordings SET preferred_revision=? WHERE id=?", (revision, record))
        db.execute("UPDATE transcript_timeline SET ended=? WHERE recording_id=?", (start + 0.1, record))
    db.close()
    return record, relative


def check(app):
    with tempfile.TemporaryDirectory(prefix="saytile-legacy-cli-", dir="/private/tmp") as scratch:
        root = Path(scratch)
        for name in ("empty-base", "empty-old"):
            path = root / name
            path.mkdir()
            (path / ".writer-lock").touch()
            db = sqlite3.connect(path / "Saytile.sqlite")
            db.execute("PRAGMA user_version=0")
            db.close()
        template = root / "template"
        command = "--merge-legacy-archive"
        run(app, command, root / "empty-base", root / "empty-old", template)
        base, old, output = [root / name for name in ("base", "old", "verified")]
        shutil.copytree(template, base)
        shutil.copytree(template, old)
        current, first_path = add_record(base, "现有合成句", 1_700_000_100)
        historic, second_path = add_record(old, "旧版合成句", 1_700_000_000)
        hashes = [digest(p / "Saytile.sqlite") for p in (base, old)]
        receipt = json.loads(run(app, command, base, old, output).stdout)
        assert receipt["examined"] == receipt["added"] == receipt["verifiedOriginals"] == 1
        assert receipt["verifiedBytes"] == 3244
        assert [digest(p / "Saytile.sqlite") for p in (base, old)] == hashes
        original_wavs = [digest(base / "Audio" / first_path), digest(old / "Audio" / second_path)]
        assert [digest(output / "Audio" / p) for p in (first_path, second_path)] == original_wavs
        with sqlite3.connect(f"file:{output}/Saytile.sqlite?mode=ro", uri=True) as database:
            rows = database.execute("SELECT recording_id FROM transcript_timeline ORDER BY position").fetchall()
            assert rows == [(historic,), (current,)]
            assert database.execute("SELECT count(*) FROM revisions").fetchone()[0] == 2
            assert database.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert database.execute("PRAGMA foreign_key_check").fetchall() == []
        run(app, command, base, old, output, success=False)
        run(app, command, base, old, base / "forbidden", success=False)
        # macOS presents /tmp and /private/tmp as aliases. An absent output
        # child must still be rejected before creating any work inside a source.
        alias = Path("/tmp") / root.name / base.name / "aliased-child"
        run(app, command, base, old, alias, success=False)
        assert not (base / "forbidden").exists() and not alias.exists()
        mistaken = root / "not-a-cloud-fixture"
        guard = run(app, "--icloud-archive-fixture", "--data-directory", mistaken, success=False)
        assert guard.returncode == 64 and not mistaken.exists()
        return {
            "status": "PASS", "records": 2, "versions": 2, "audio_bytes": 6488,
            "wav_sha256": original_wavs, "sources_unchanged": True, "chronological": True,
            "new_output_only": True, "malformed_cloud_fixture_stopped_before_opening_archive": True,
            "cloud_calls": 0
        }


if __name__ == "__main__":
    print(json.dumps(check(Path(sys.argv[1]).resolve(strict=True)), indent=2))
