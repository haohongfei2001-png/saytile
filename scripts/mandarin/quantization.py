"""Compare two verified ONNX exports with identical CPU worker, PCM, chunks and greedy decoding."""

import argparse, hashlib, json, struct, subprocess, tempfile, wave
from pathlib import Path

parser = argparse.ArgumentParser()
for name in ("worker", "model", "tokens", "audio", "manifest", "output"):
    parser.add_argument("--" + name, type=Path, required=True)
parser.add_argument("--precision", choices=["fp32", "int8"], required=True)
args = parser.parse_args()
known = {
    "int8": "24ffdc19ba9aaed5a6a9beaede1e087745217d82425cf4041bca0c696661801e",
    "fp32": "44ca070d4caf18f9d831adfc57ca7cdd44c4060ff0b822fa1926b713cc570d70",
}


def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


assert digest(args.model) == known[args.precision]
catalog = json.loads(
    Path("Sources/SaytileKit/Resources/LocalASR/zipformer.json").read_text()
)
assert digest(args.tokens) == next(
    x["sha256"] for x in catalog["files"] if x["path"] == "tokens.txt"
)
with tempfile.TemporaryDirectory(prefix="saytile-ctc-ab-") as scratch:
    p = Path(scratch)
    # The production C ABI adapter uses one fixed filename; the artifact SHA selects precision.
    (p / "model.int8.onnx").symlink_to(args.model.resolve())
    (p / "tokens.txt").symlink_to(args.tokens.resolve())
    with subprocess.Popen(
        [args.worker, "zipformer", p, "0"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    ) as proc:
        assert json.loads(proc.stdout.readline())["kind"] == "ready"
        with args.output.open("x") as out:
            for row in json.loads(args.manifest.read_text()):
                audio = args.audio / (row["id"] + ".wav")
                assert digest(audio) == row["audio_sha256"]
                with wave.open(str(audio)) as w:
                    assert (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (
                        16000,
                        1,
                        2,
                    )
                    while block := w.readframes(3200):
                        proc.stdin.write(struct.pack("<I", len(block)) + block)
                proc.stdin.write(bytes(4))
                proc.stdin.flush()
                while event := json.loads(proc.stdout.readline()):
                    if event["kind"] == "final":
                        break
                assert event["kind"] == "final"
                out.write(
                    json.dumps(
                        {
                            "id": row["id"],
                            "model": "zipformer",
                            "precision": args.precision,
                            "text": event["text"],
                        },
                        ensure_ascii=False,
                    )
                    + "\n"
                )
                out.flush()
        proc.stdin.close()
        assert proc.wait(timeout=10) == 0
