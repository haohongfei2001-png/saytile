"""Check exact-PCM EOS reuse on the signed worker and one hash-pinned public WAV."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import struct
import subprocess
import wave


def run(app, weights, audio):
    item = json.loads(Path("evidence/mandarin-cadence-20261114/worker-cases.json").read_text())["samples"][0]
    path = audio / (item["id"] + ".wav")
    assert hashlib.sha256(path.read_bytes()).hexdigest() == item["audio_sha256"]
    with wave.open(str(path)) as source:
        assert (source.getframerate(), source.getnchannels(), source.getsampwidth()) == (16000, 1, 2)
        pcm = source.readframes(source.getnframes())
    manifest = json.loads(Path("Sources/SaytileKit/Resources/LocalASR/qwen-small.json").read_text())
    binary = app / "Contents/Helpers/SaytileModelWorker"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    with subprocess.Popen([binary, "qwen-small", weights / "qwen-small" / manifest["revision"], "8000"],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          cwd=app / "Contents/Resources", env=dict(os.environ, SAYTILE_WORKER_TIMING="1")) as worker:
        def send(payload):
            worker.stdin.write(struct.pack("<I", len(payload)) + payload)
            worker.stdin.flush()

        with selectors.DefaultSelector() as sel:
            sel.register(worker.stdout, selectors.EVENT_READ)

            def receive():
                assert sel.select(timeout=30), "worker output timeout"
                return json.loads(worker.stdout.readline())

            try:
                assert receive()["kind"] == "ready"
                # Withhold EOS until a real partial returns. A second utterance
                # has identical preview PCM but one extra 20 ms packet before EOS.
                for extra in [0, 320]:
                    offset = 12_800
                    send(pcm[:2 * offset])
                    event = receive()
                    assert event["kind"] == "partial" and event["frames"] == offset and event["text"]
                    if extra:
                        send(pcm[2 * offset:2 * (offset + extra)])
                    send(b"")
                    final = receive()
                    assert final["kind"] == "final" and final["frames"] == offset + extra
                    assert len([d for d in final.get("decodes", []) if d["final"]]) == int(bool(extra))
                    if not extra:
                        assert final["text"] == event["text"]
                    print(json.dumps(dict(extra_pcm_frames=extra, final_frames=offset + extra,
                                          decoded_again=bool(extra), public_audio_sha256=item["audio_sha256"])))
                send(b"")
                empty = receive()
                assert empty["kind"] == "final" and empty["frames"] == 0 and empty["text"] == ""
            finally:
                worker.stdin.close()
                if worker.poll() is None:
                    try:
                        worker.wait(timeout=4)
                    except subprocess.TimeoutExpired:
                        worker.kill()
                        worker.wait()
            assert worker.returncode == 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ["app", "weights", "audio"]:
        parser.add_argument("--" + arg, required=True, type=lambda value: Path(value).resolve())
    run(**vars(parser.parse_args()))
