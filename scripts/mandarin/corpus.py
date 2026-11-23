"""Freeze rows before inference. No audio leaves the evaluation host."""

import hashlib, io, json, sys
from pathlib import Path
import numpy as np, pyarrow.parquet as pq, soundfile as sf

root = Path(".build/mandarin")
wav = root / "wav"
wav.mkdir(exist_ok=True, parents=True)
manifest = []
seen = set()


def h(v):
    return hashlib.sha256(v).hexdigest()


def take(path, corpus, n, rev, sha, language=None):
    with path.open("rb") as source:
        assert hashlib.file_digest(source, "sha256").hexdigest() == sha
    candidates = []
    for batch in pq.ParquetFile(path).iter_batches(batch_size=32):
        for r in batch.to_pylist():
            audio = r.get("audio") or r.get("context")
            ref = (
                r.get("raw_transcription")
                or r.get("transcription")
                or r.get("text")
                or r.get("sentence")
                or r.get("answer")
            )
            if not ref or "[UNK]" in ref or (language and r["language"] != language):
                continue
            key = str(r.get("id") or audio["path"] or h(audio["bytes"]))
            if ref in seen:
                continue
            seen.add(ref)
            candidates.append((h((corpus + key).encode()), key, ref, audio["bytes"]))
    candidates.sort()
    count = 0
    for _, key, ref, b in candidates:
        x, sr = sf.read(io.BytesIO(b))
        assert sr == 16000
        if not 1.2 <= len(x) / sr <= 26:
            continue
        ident = corpus + "-" + h(key.encode())[:16]
        p = wav / (ident + ".wav")
        sf.write(p, x, sr, subtype="PCM_16")
        manifest.append(
            dict(
                id=ident,
                source=corpus,
                row=key,
                revision=rev,
                reference=ref,
                audio_sha256=h(p.read_bytes()),
                duration=len(x) / sr,
            )
        )
        count += 1
        if count == n:
            break
    assert count == n, (corpus, count)


if sys.argv[1] == "aishell":
    take(
        root / "air.parquet",
        "aishell1-test",
        100,
        "e73dc7f096ecea5c8e5c722446c8d3b4014fdd18",
        "2466b1e851147943d4a2c46e1dddc8a70a45b733065c7f6a86e44bd88d5579c6",
    )
else:
    take(
        Path(sys.argv[2]),
        "fleurs",
        160,
        "70bb2e84b976b7e960aa89f1c648e09c59f894dd",
        "87c0aebbe183f3a36ac87b5c3421b6ab57036824744ff695029a3f858e7622fd",
    )
    for lang in ("zh", "mixed"):
        take(
            root / "asc.parquet",
            "ascend-" + lang,
            80,
            "737e9800ae31be9932ba8464c80366559bd28424",
            "a4c81d2b5ed6124f052089a695972808c16e0ce0c365ec9773c5d1a8fcf043a7",
            lang,
        )
    for i, r in enumerate(manifest[:20]):
        x, sr = sf.read(wav / (r["id"] + ".wav"))
        mode = "quiet" if i % 2 == 0 else "noise15db"
        y = (
            x * 0.1
            if mode == "quiet"
            else x
            + np.random.default_rng(i).normal(
                0, np.sqrt(np.mean(x * x)) * 10 ** (-15 / 20), len(x)
            )
        )
        id = r["id"] + "-" + mode
        p = wav / (id + ".wav")
        sf.write(p, y, sr, subtype="PCM_16")
        manifest.append(
            {**r, "id": id, "source": mode, "audio_sha256": h(p.read_bytes())}
        )
Path("evidence/mandarin/" + sys.argv[1] + ".json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=1) + "\n"
)
