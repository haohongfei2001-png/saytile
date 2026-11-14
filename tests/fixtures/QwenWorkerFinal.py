"""Check exact-PCM finals and optional verified-preview EOS against the reference worker."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import struct
import subprocess
import wave


def run(app, weights, audio, reference_app=None):
    cases = json.loads(Path("evidence/mandarin-cadence-20261114/worker-cases.json").read_text())["samples"]
    item = cases[0]
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
                if reference_app:
                    long_case = next(row for row in cases if row["id"] == "continuous-public-5")
                    long_file = audio / (long_case["id"] + ".wav")
                    assert hashlib.sha256(long_file.read_bytes()).hexdigest() == long_case["audio_sha256"]
                    with wave.open(str(long_file)) as named:
                        assert (named.getframerate(), named.getnchannels(), named.getsampwidth()) == (16000, 1, 2)
                        long_pcm = named.readframes(16_000 * 12)
                    offset = 0
                    receipt = []
                    # All chunks have exactly the same acoustic boundaries. Wait for
                    # the known public phrase to change before providing more audio.
                    for boundary in [12_800, 44_800, 76_800, 108_800, 140_800, 172_800]:
                        send(long_pcm[2 * offset:2 * boundary])
                        update = receive()
                        assert update["kind"] == "partial" and update["frames"] == boundary
                        receipt.extend(update.get("decodes", []))
                        offset = boundary
                    assert any(row["verifiedPreviewTokens"] > 0 for row in receipt)
                    send(b"")
                    confirmed = receive()
                    assert confirmed["kind"] == "final" and confirmed["frames"] == offset
                    end = [row for row in confirmed.get("decodes", []) if row["final"]]
                    assert len(end) == 1 and end[0]["verifiedPreviewTokens"] == 0
                    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(reference_app)], check=True)
                    stream = bytearray()
                    for begin in range(0, offset, 16_000):
                        part = long_pcm[2 * begin:2 * min(begin + 16_000, offset)]
                        stream += struct.pack("<I", len(part)) + part
                    stream += bytes(4)
                    # The reference runs with a distinct process only after the
                    # candidate is idle. Both read the same immutable weights.
                    result = subprocess.run([reference_app / "Contents/Helpers/SaytileModelWorker",
                                             "qwen-small", weights / "qwen-small" / manifest["revision"], "8000"],
                                            input=stream, stdout=subprocess.PIPE, check=True, timeout=60,
                                            cwd=reference_app / "Contents/Resources")
                    expected = json.loads(result.stdout.splitlines()[-1])
                    assert expected["kind"] == "final" and expected["frames"] == offset
                    assert confirmed["text"] == expected["text"]
                    print(json.dumps(dict(public_audio_sha256=long_case["audio_sha256"], frames=offset,
                                          verified_tokens=[r["verifiedPreviewTokens"] for r in receipt],
                                          final_greedy_recomputed=True, equal_to_reference=True)))
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
    parser.add_argument("--reference-app", type=lambda value: Path(value).resolve())
    run(**vars(parser.parse_args()))
