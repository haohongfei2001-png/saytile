"""One bounded, same-PCM-call-order native helper comparison; not a realtime benchmark.

Uses the existing QwenWorkerFinal framed protocol and approved public WAV.
Each input boundary is supplied only after the previous partial. No extra PCM,
retry, or invented output is used when the old helper suppresses an event.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import plistlib
import selectors
import struct
import subprocess
import time
import wave

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=False)
task = Path("/private/tmp/saytile-response-bench")
repo = Path("/private/tmp/saytile-asr-response")
boundaries = json.loads((task / "fixed-worker-boundaries.json").read_text())
audio = Path("/private/tmp/saytile-local-quality-20261114/.build/mandarin/bench/final-long-wav/continuous-public-5.wav")
weights = Path("/private/tmp/saytile-local-quality-20261114/.build/local-asr/weights/qwen-small/bc441bd1e4295c1f42d9879f056049a925b6e013")
assert hashlib.sha256(audio.read_bytes()).hexdigest() == boundaries["audio_sha256"]
with wave.open(str(audio)) as source:
    assert (source.getframerate(), source.getnchannels(), source.getsampwidth()) == (16000, 1, 2)
    pcm = source.readframes(boundaries["final_boundary"])
apps = {"baseline": task / "baseline-484.app", "candidate": task / "clean-paired486/candidate.app"}
libproc = ctypes.CDLL("/usr/lib/libproc.dylib")


def current_processes():
    return [line.strip() for line in subprocess.check_output(["ps", "-axo", "pid=,ppid=,pcpu=,comm="], text=True).splitlines()
            if any(part in line for part in ["Saytile", "swift-frontend", "swiftc", "clang"])]


def run(arm, app):
    before = current_processes()
    if any(any(part in line for part in ["SaytileModelWorker", "SaytileSherpa", "swift-frontend", "swiftc", "clang"]) for line in before):
        raise RuntimeError("Existing inference or compiler is active; preserve it and stop this run")
    binary = app / "Contents/Helpers/SaytileModelWorker"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    result = {"arm": arm, "source": info["SaytileSourceRevision"], "build": info["CFBundleVersion"],
              "worker_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
              "audio_sha256": boundaries["audio_sha256"], "input_pcm_sha256": hashlib.sha256(pcm).hexdigest(),
              "preview_boundaries": boundaries["preview_boundaries"], "final_boundary": boundaries["final_boundary"],
              "before_processes": before, "load_before": os.getloadavg(), "events": [], "samples": [], "status": "RUNNING"}
    start = time.monotonic()
    phase = "load"
    with (out / (arm + ".stderr.log")).open("w") as errors:
        worker = subprocess.Popen([binary, "qwen-small", weights, "8000"], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=errors, cwd=app / "Contents/Resources",
                                  env=dict(os.environ, SAYTILE_WORKER_TIMING="1"))

        def sample():
            data = (ctypes.c_uint64 * 12)()
            if libproc.proc_pid_rusage(worker.pid, 0, ctypes.byref(data)) == 0:
                result["samples"].append({"t": time.monotonic() - start, "phase": phase,
                                          "physical_footprint_bytes": data[9], "resident_bytes": data[8]})

        def send(payload):
            assert len(payload) <= 65536 and len(payload) % 2 == 0
            worker.stdin.write(struct.pack("<I", len(payload)) + payload)
            worker.stdin.flush()

        with selectors.DefaultSelector() as selector:
            selector.register(worker.stdout, selectors.EVENT_READ)

            def receive(kind, frames):
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    sample()
                    if selector.select(timeout=.025):
                        line = worker.stdout.readline()
                        if not line:
                            raise RuntimeError("Helper exited before expected " + kind)
                        event = json.loads(line)
                        result["events"].append({"observed_at_s": time.monotonic() - start, **event})
                        sample()
                        if event["kind"] != kind or event["frames"] != frames:
                            raise RuntimeError("Unexpected event or PCM boundary: " + str(event))
                        return event
                raise TimeoutError(f"No {kind} at exact {frames} frames; no retry or added PCM")

            try:
                receive("ready", 0)
                offset = 0
                for boundary in boundaries["preview_boundaries"]:
                    phase = "preview-" + str(boundary)
                    send(pcm[offset * 2:boundary * 2])
                    assert receive("partial", boundary)["text"]
                    offset = boundary
                phase = "final-" + str(boundaries["final_boundary"])
                send(pcm[offset * 2:])
                send(b"")
                final = receive("final", boundaries["final_boundary"])
                assert final["text"]
                assert all(d.get("verifiedPreviewTokens", 0) == 0 for d in final.get("decodes", []) if d["final"])
                sample()
                cpu = subprocess.check_output(["ps", "-p", str(worker.pid), "-o", "time="], text=True).strip()
                result["helper_cpu_time_before_exit"] = cpu
                result["status"] = "PASS"
            except Exception as error:
                result["status"] = "FAIL"
                result["error"] = repr(error)
                raise
            finally:
                worker.stdin.close()
                try:
                    worker.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    worker.terminate()
                    worker.wait(timeout=4)
                result["exit_code"] = worker.returncode
                result["wall_s"] = time.monotonic() - start
                result["load_after"] = os.getloadavg()
                if result["samples"]:
                    result["peak"] = max(result["samples"], key=lambda row: row["physical_footprint_bytes"])
                (out / (arm + ".json")).write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
                print(arm, result["status"], result.get("peak"), flush=True)
        assert worker.returncode == 0
    return result


first = run("baseline", apps["baseline"])
second = run("candidate", apps["candidate"])
pairs = [{"kind": a["kind"], "frames": a["frames"], "same_text": a["text"] == b["text"],
          "baseline_decodes": a.get("decodes", []), "candidate_decodes": b.get("decodes", [])}
         for a, b in zip(first["events"], second["events"], strict=True)]
assert all(a["kind"] == b["kind"] and a["frames"] == b["frames"]
           for a, b in zip(first["events"], second["events"], strict=True))
report = {"scope": "Fixed input calls, read-only native worker control; not realtime timing, AppKit, microphone, or 8GB acceptance",
          "raw_partial_and_final_texts_identical": all(row["same_text"] for row in pairs),
          "final_text_identical": pairs[-1]["same_text"], "pairs": pairs,
          "baseline_peak": first["peak"], "candidate_peak": second["peak"],
          "baseline_cpu_time": first["helper_cpu_time_before_exit"], "candidate_cpu_time": second["helper_cpu_time_before_exit"]}
(out / "comparison.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print("FIXED_PCM_CONTROL_COMPLETE", report["raw_partial_and_final_texts_identical"], flush=True)
