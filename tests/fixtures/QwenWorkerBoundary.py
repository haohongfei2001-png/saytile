"""Compare exact 32-second window and independent EOS on pinned public PCM."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import wave


def load_pcm(path, checksum):
    assert hashlib.sha256(path.read_bytes()).hexdigest() == checksum
    with wave.open(str(path)) as audio:
        assert (audio.getframerate(), audio.getnchannels(), audio.getsampwidth()) == (16000, 1, 2)
        return audio.readframes(audio.getnframes())


def run(app, reference_app, weights, audio, output):
    source = Path("evidence/mandarin-cadence-20261114/worker-cases.json")
    cases = json.loads(source.read_text())["samples"]
    long = next(row for row in cases if row["id"] == "continuous-public-5")
    short = cases[0]
    samples = [load_pcm(audio / (row["id"] + ".wav"), row["audio_sha256"]) for row in [long, short]]
    # Force the window transition exactly at PCM frame 512000 for both helpers.
    wire = bytearray()
    for pcm in samples:
        for begin in range(0, len(pcm), 6400):
            packet = pcm[begin:begin + 6400]
            wire += struct.pack("<I", len(packet)) + packet
        wire += bytes(4)
    wire += bytes(4)
    manifest = json.loads(Path("Sources/SaytileKit/Resources/LocalASR/qwen-small.json").read_text())
    arms = []
    for path in [reference_app, app]:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(path)], check=True)
        helper = path / "Contents/Helpers/SaytileModelWorker"
        result = subprocess.run([helper, "qwen-small", weights / "qwen-small" / manifest["revision"], "8000"],
                                input=wire, stdout=subprocess.PIPE, check=True, timeout=120,
                                cwd=path / "Contents/Resources",
                                env=dict(os.environ, SAYTILE_WORKER_TIMING="1"))
        events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith(b'{"')]
        extra = [line.decode(errors="replace") for line in result.stdout.splitlines() if not line.startswith(b'{"')]
        assert set(extra) <= {
                        "Found 1 safetensor files", "Loading: model.safetensors",
                        "Applied weights to audio encoder (18 layers, 301 tensors)",
                        "Applied weights to text decoder (28 layers, 704 tensors)",
                    }, extra
        finals = [event for event in events if event["kind"] == "final"]
        assert [event["frames"] for event in finals] == [len(pcm) // 2 for pcm in samples] + [0]
        assert finals[-1]["text"] == ""
        assert finals[0]["text"] and finals[1]["text"] and finals[0]["text"] != finals[1]["text"]
        traces = [decode for event in events for decode in event.get("decodes", [])]
        boundary = [decode for decode in traces if decode["frames"] == 512000 and not decode["final"]]
        assert len(boundary) == 1, "window boundary did not run exactly once"
        assert boundary[0].get("verifiedPreviewTokens", 0) == 0, "window froze a verified preview"
        assert all(row.get("verifiedPreviewTokens", 0) == 0 for row in traces if row["final"])
        metadata = plistlib.loads((path / "Contents/Info.plist").read_bytes())
        arms.append({
            "source": metadata["SaytileSourceRevision"], "dirty": metadata["SaytileSourceDirty"],
            "build": metadata["CFBundleVersion"],
            "helper_sha256": hashlib.sha256(helper.read_bytes()).hexdigest(),
            "stdout_nonprotocol": extra, "raw_finals": [event["text"] for event in finals],
            "final_frames": [event["frames"] for event in finals],
            "decodes": traces,
        })
    assert arms[0]["raw_finals"] == arms[1]["raw_finals"], "window/EOS transcript differs from original greedy"
    for arm in arms:
        arm["final_utf16_lengths"] = [len(text.encode("utf-16-le")) // 2 for text in arm["raw_finals"]]
        arm["final_text_sha256"] = [hashlib.sha256(text.encode()).hexdigest() for text in arm.pop("raw_finals")]
    receipt = {
        "status": "PASS", "protocol": "Sequential original and candidate helpers. Identical 0.2s packets, 32s window, 38.8s whole stream, 6s independent next segment, empty EOS. No microphone or native-window acceptance inferred.",
        "input_sha256": [row["audio_sha256"] for row in [long, short]],
        "wire_sha256": hashlib.sha256(wire).hexdigest(), "arms": arms,
    }
    output.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"status": "PASS", "output": str(output), "final_frames": arms[1]["final_frames"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ["app", "reference-app", "weights", "audio", "output"]:
        parser.add_argument("--" + arg, required=True, type=lambda value: Path(value).resolve())
    run(**vars(parser.parse_args()))
