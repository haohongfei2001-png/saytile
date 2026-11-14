"""Measure native partials and process CPU in one isolated wall-paced public replay.

The Darwin sampled cumulative CPU time is taken from ps time= (1/100 second).
Each PID's maximum observed counter is a lower bound if it exits between samples.
Wall time includes model startup and EOS. No real microphone, accounts or archives.
"""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time

LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib")


def seconds(cpu_time):
    minutes, secs = cpu_time.rsplit(":", 1)
    if ":" in minutes:
        hours, minutes = minutes.split(":")
        return int(hours) * 3600 + int(minutes) * 60 + float(secs)
    return int(minutes) * 60 + float(secs)


def public_run(app, manifest, sample_id, weights, audio, out):
    meta = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    row = next(r for r in json.loads(manifest.read_text())["samples"] if r["id"] == sample_id)
    wav = audio / (sample_id + ".wav")
    assert hashlib.sha256(wav.read_bytes()).hexdigest() == row["audio_sha256"]
    out.mkdir(parents=True, exist_ok=False)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", app], check=True)
    with tempfile.TemporaryDirectory(prefix="saytile-native-cost-") as tmp:
        data = Path(tmp)
        shutil.copyfile(wav, data / "fixture.wav")
        (data / "LocalModels").mkdir()
        subprocess.run(["cp", "-cR", weights / "qwen-small", data / "LocalModels"], check=True)
        with tempfile.TemporaryFile() as log:
            start = time.monotonic()
            p = subprocess.Popen([app / "Contents/MacOS/Saytile", "--data-directory", data,
                                  "--local-stream-probe", "auto"], stdout=log, stderr=log)
            samples, children, last_cpu = [], set(), {}
            try:
                while p.poll() is None:
                    if time.monotonic() - start > 100:
                        raise TimeoutError(sample_id)
                    child_pids = (ctypes.c_int * 16)()
                    count = LIBPROC.proc_listchildpids(p.pid, child_pids, ctypes.sizeof(child_pids))
                    active = [pid for pid in child_pids if pid > 0]
                    assert len(active) <= 1 and count < ctypes.sizeof(child_pids), active
                    children.update(active)
                    ids = [p.pid, *active]
                    process_times = subprocess.run(["ps", "-p", ",".join(map(str, ids)), "-o", "pid=,time="],
                                                   capture_output=True, text=True)
                    observed = {int(pid): seconds(t) for line in process_times.stdout.splitlines()
                                for pid, t in [line.split()]}
                    # ps can reset the last line to zero for a just-exited process.
                    # CPU time is cumulative for the lifetime of this child.
                    for pid, cpu in observed.items():
                        last_cpu[pid] = max(last_cpu.get(pid, 0), cpu)
                    footprint = {}
                    for pid, role in [(p.pid, "app"), *((i, "worker") for i in active)]:
                        info = (ctypes.c_uint64 * 12)()
                        if LIBPROC.proc_pid_rusage(pid, 0, ctypes.byref(info)) == 0:
                            footprint[role] = info[9]
                    samples.append(dict(t=round(time.monotonic() - start, 3),
                                        app_cpu_s=observed.get(p.pid),
                                        workers_cpu_s=round(sum(last_cpu.get(i, 0) for i in children), 3),
                                        footprint=footprint))
                    time.sleep(.20)
            finally:
                if p.poll() is None:
                    p.terminate()
                    p.wait(timeout=4)
            elapsed = time.monotonic() - start
            assert p.returncode == 0, p.returncode
        receipt = json.loads((data / "visible.json").read_text())
        assert receipt["sha"] == meta["SaytileSourceRevision"]
        assert receipt["automatic"] and receipt["providers"] == ["qwen-small"]
        assert all(v == "completed" for v in receipt["recordStates"]) and len(receipt["archive"]) > 0
        assert receipt["frames"][-1]["text"] == "".join(reversed(receipt["archive"]))
        assert receipt["rawWorkerEvents"] and receipt["publications"]
        assert children and {p.pid, *children} <= last_cpu.keys()
        receipt.update(exit_code=p.returncode, audio_sha256=row["audio_sha256"], id=sample_id)
        (out / f"auto-qwen-small-{sample_id}.json").write_text(json.dumps(receipt, ensure_ascii=False) + "\n")
    worker_s = sum(last_cpu[pid] for pid in children)
    total_s = last_cpu[p.pid] + worker_s
    raw = receipt["rawWorkerEvents"]
    decodes = [d for e in raw for d in e.get("decodes") or [] if not d["final"]]
    result = dict(source=meta["SaytileSourceRevision"], build=meta["CFBundleVersion"], sample=sample_id,
                  audio_sha256=row["audio_sha256"], wall_s=round(elapsed, 3), app_cpu_s=last_cpu[p.pid],
                  workers_cpu_s=round(worker_s, 3), combined_cpu_s=round(total_s, 3),
                  process_equivalent_cores=round(total_s / elapsed, 4),
                  input_s=row["duration"], end_of_file=receipt["endOfFile"],
                  peak_simultaneous_footprint_MiB=round(max(sum(s["footprint"].values()) for s in samples)/2**20, 1),
                  computes=len(decodes), preview_compute_wall_s=round(sum(d["endUptime"]-d["startUptime"] for d in decodes),3),
                  samples=samples)
    (out / "process.json").write_text(json.dumps(result, indent=1) + "\n")
    print(json.dumps({k:v for k,v in result.items() if k!="samples"}), flush=True)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    for name in ["app", "manifest", "weights", "audio", "out"]:
        cli.add_argument("--" + name, type=Path, required=True)
    cli.add_argument("--id", dest="sample_id", required=True)
    public_run(**vars(cli.parse_args()))
