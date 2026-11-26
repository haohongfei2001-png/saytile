#!/usr/bin/env python3
"""One real Qwen acoustic smoke; no microphone, accuracy score, or speed claim."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import signal
import subprocess
import sys
import tempfile
import time
import wave

ROOT = Path(__file__).resolve().parents[1]
SAMPLE_SHA = "5d29f5fc799a571b27d80bcf442004ba78a619c0d6e847258bb2b6b8b075387a"
SAMPLE_ID = "bundled-synthetic-with-preroll"
METAL_PROBE = """
import Foundation
import Metal
import CoreGraphics

var result: [String: Any]
if let device = MTLCreateSystemDefaultDevice() {
    guard let queue = device.makeCommandQueue(),
          let command = queue.makeCommandBuffer() else {
        throw NSError(domain: "SaytileMetalSmoke", code: 1)
    }
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
        throw command.error ?? NSError(domain: "SaytileMetalSmoke", code: 2)
    }
    result = ["available": true, "device": device.name,
              "command_status": command.status.rawValue]
} else {
    result = ["available": false, "reason": "MTLCreateSystemDefaultDevice returned nil"]
}
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
"""


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def file_sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def preflight(output, source):
    # Command-line Metal must link CoreGraphics to obtain the default device.
    with tempfile.TemporaryDirectory(prefix="saytile-metal-smoke-") as directory:
        root = Path(directory)
        code, binary = root / "MetalProbe.swift", root / "MetalProbe"
        code.write_text(METAL_PROBE)
        with (output / "metal.log").open("w") as log:
            subprocess.run(["swiftc", "-swift-version", "6", "-framework", "Metal",
                            "-framework", "CoreGraphics", code, "-o", binary],
                           stdout=log, stderr=subprocess.STDOUT, timeout=60, check=True)
            subprocess.run([binary, output / "metal.json"], stdout=log,
                           stderr=subprocess.STDOUT, timeout=15, check=True)
    result = json.loads((output / "metal.json").read_text())
    result.update(source=source, architecture=platform.machine(), macos=platform.mac_ver()[0])
    write(output / "metal.json", result)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
            stream.write(f"available={str(result['available']).lower()}\n")
    return result


def smoke(app, output, source, receipt):
    metal = json.loads((output / "metal.json").read_text())
    assert metal["source"] == source and metal["available"], metal
    meta = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert meta["SaytileSourceRevision"] == source and not meta["SaytileSourceDirty"], meta
    subprocess.run(["codesign", "--verify", "--deep", "--strict", app], timeout=30, check=True)
    manifest = json.loads((ROOT / "Sources/SaytileKit/Resources/LocalASR/qwen-small.json").read_text())
    pcm_path = ROOT / "Sources/SaytileKit/Resources/ConnectionSample.pcm"
    assert file_sha(pcm_path) == SAMPLE_SHA
    pcm = bytes(12_800 * 2) + pcm_path.read_bytes()
    assert len(pcm) % 2 == 0
    receipt.update(model=manifest["id"], model_revision=manifest["revision"],
                   model_bytes=sum(item["bytes"] for item in manifest["files"]),
                   original_pcm_sha256=SAMPLE_SHA, pre_roll_frames=12_800,
                   expected_frames=len(pcm) // 2,
                   scope="one bundled synthetic acoustic smoke; no accuracy or performance comparison")
    write(output / "model-manifest.json", manifest)
    write(output / "receipt.json", receipt)
    # Weights/audio are disposable and are never included in CI caches/artifacts.
    with tempfile.TemporaryDirectory(prefix="saytile-qwen-smoke-") as directory:
        root = Path(directory)
        weights = root / "weights"
        model_root = weights / manifest["id"] / manifest["revision"]
        model_root.mkdir(parents=True)
        deadline = time.monotonic() + 240
        with (output / "download.log").open("w") as log:
            for item in manifest["files"]:
                target = model_root / item["path"]
                target.parent.mkdir(parents=True, exist_ok=True)
                remaining = max(1, int(deadline - time.monotonic()))
                url = f"https://huggingface.co/{manifest['repo']}/resolve/{manifest['revision']}/{item['path']}"
                subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                                "--connect-timeout", "15", "--max-time", str(remaining),
                                url, "--output", target], stdout=log, stderr=subprocess.STDOUT,
                               timeout=remaining + 1, check=True)
                assert target.stat().st_size == item["bytes"] and file_sha(target) == item["sha256"], item["path"]
        audio = root / (SAMPLE_ID + ".wav")
        with wave.open(str(audio), "wb") as wav:
            wav.setparams((1, 2, 16_000, 0, "NONE", "not compressed"))
            wav.writeframes(pcm)
        fixture = output / "fixture.json"
        write(fixture, {"samples": [{"id": SAMPLE_ID, "audio_sha256": file_sha(audio),
                                    "reference": "", "source": "Saytile bundled synthetic ConnectionSample",
                                    "duration": len(pcm) / 32_000}]})
        receipt["fixture_wav_sha256"] = file_sha(audio)
        write(output / "receipt.json", receipt)
        # Reuse the existing 40 ms paced helper unchanged. The pipe unit probe,
        # not this acoustic smoke, proves already-queued first-window coalescing.
        command = [sys.executable, ROOT / "scripts/bench-local-asr.py", "--model", "qwen-small",
                   "--chunk", "0.5", "--runtime", app / "Contents/Helpers", "--weights", weights,
                   "--audio", root, "--paired", fixture, "--ids", SAMPLE_ID,
                   "--output", output / "worker.json"]
        with (output / "worker.log").open("w") as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                       env={**os.environ, "SAYTILE_WORKER_TIMING": "1"},
                                       start_new_session=True)
            try:
                assert process.wait(timeout=150) == 0, "real Qwen worker helper failed; see worker.log"
            finally:
                # Also reap an owned worker if the helper timed out or failed.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
        result = json.loads((output / "worker.json").read_text())
        assert result["status"] == "PASS" and len(result["samples"]) == 1
        events = result["samples"][0]["events"]
        partials = [event for event in events if event["kind"] == "partial" and event["text"].strip()]
        finals = [event for event in events if event["kind"] == "final"]
        assert partials and len(finals) == 1, events
        final = finals[0]
        assert final["frames"] == len(pcm) // 2, final
        assert sum(character.isalnum() for character in final["text"]) >= 4, final
        frames = [event["frames"] for event in events]
        assert frames == sorted(frames) and all(0 < value <= len(pcm) // 2 for value in frames), frames
        assert file_sha(pcm_path) == SAMPLE_SHA
        with wave.open(str(audio), "rb") as wav:
            assert wav.readframes(wav.getnframes()) == pcm
        receipt.update(status="PASS", partial_count=len(partials), final_count=1,
                       final_frames=final["frames"], final_text=final["text"],
                       original_pcm_unchanged=True, source_build=meta["CFBundleVersion"])
        write(output / "receipt.json", receipt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--app", type=Path, default=ROOT / "dist/Saytile.app")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    receipt = {"status": "NOT_RUN", "source": source}
    try:
        if args.preflight_only:
            metal = preflight(output, source)
            receipt.update(status="NOT_RUN" if metal["available"] else "BLOCKED", metal=metal)
            if not metal["available"]:
                receipt["reason"] = metal["reason"]
            write(output / "receipt.json", receipt)
        else:
            smoke(args.app.resolve(), output, source, receipt)
    except Exception as error:
        receipt.update(status="FAIL", reason=f"{type(error).__name__}: {error}")
        write(output / "receipt.json", receipt)
        print(json.dumps(receipt, ensure_ascii=False), file=sys.stderr)
        return 1
    print(json.dumps(receipt, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
