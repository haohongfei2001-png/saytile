"""Unprivileged isolated panel replay. Record separate idle and active system readings."""

import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import signal
import statistics
import subprocess as sp
import tempfile
import time

libproc = ctypes.CDLL("/usr/lib/libproc.dylib")


def footprint(pid):
    # Darwin rusage_info_v0: 16-byte UUID followed by ten 64-bit counters.
    info = (ctypes.c_uint64 * 12)()
    if libproc.proc_pid_rusage(pid, 0, ctypes.byref(info)) == 0:
        cpu = command("ps", "-p", str(pid), "-o", "pcpu=")
        return {
            "rss": info[8],
            "physical": info[9],
            "cpu_percent": float(cpu) if cpu else None,
        }
    return None


def command(*args):
    return sp.run(args, capture_output=True, text=True).stdout.strip()


def ids(*args):
    return [int(n) for n in command("pgrep", *args).split()]


def pressure():
    return {
        "pressure": command("sysctl", "-n", "kern.memorystatus_vm_pressure_level"),
        "swap": command("sysctl", "-n", "vm.swapusage"),
        "battery": re.sub(r" \(id=\d+\)", "", command("pmset", "-g", "batt")),
    }


def measure(label, meter, start):
    with tempfile.TemporaryFile(mode="w+") as log:
        monitor = sp.Popen([meter, "pipe", "-i", "1000"], stdout=log, stderr=sp.DEVNULL)
        launch = time.monotonic()
        proc = start()
        snapshots = []
        state = pressure()
        try:
            while proc.poll() is None if proc else time.monotonic() - launch < 9:
                if time.monotonic() - launch > 100:
                    raise TimeoutError(label)
                children = ids("-P", str(proc.pid)) if proc else []
                assert len(children) <= 1, children
                speech = ids("-x", "localspeechrecognition")

                def sample(group):
                    return [x for pid in group if (x := footprint(pid))]

                broker_names = ("corespeechd", "corespeechd_system", "aneuserd")
                brokers = {name: sample(ids("-x", name)) for name in broker_names}
                snapshots.append(
                    dict(
                        t=round(time.monotonic() - launch, 3),
                        app=sample([proc.pid]) if proc else [],
                        helper=sample(children),
                        speech=sample(speech),
                        shared_services=brokers,
                        speech_pid_count=len(speech),
                    )
                )
                time.sleep(0.35)
        finally:
            if proc and proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=5)
            monitor.send_signal(signal.SIGTERM)
            try:
                monitor.wait(timeout=4)
            except sp.TimeoutExpired:
                monitor.kill()
                monitor.wait()
        log.seek(0)
        samples = []
        for line in log:
            try:
                value = json.loads(line)
            except ValueError:
                continue
            samples.append(
                {
                    k: value[k]
                    for k in (
                        "sys_power",
                        "cpu_power",
                        "gpu_power",
                        "ane_power",
                        "cpu_active_ratio",
                        "gpu_active_ratio",
                    )
                }
            )
        assert len(samples) >= 3, label
        peaks = {
            k: max(sum(r["physical"] for r in s[k]) for s in snapshots)
            for k in ("app", "helper", "speech")
        }
        peak = max(
            sum(r["physical"] for k in ("app", "helper") for r in s[k])
            for s in snapshots
        )
        return dict(
            label=label,
            observed_seconds=round(time.monotonic() - launch, 2),
            initial=state,
            end=pressure(),
            app_and_helper_simultaneous_peak_bytes=peak,
            peak_bytes=peaks,
            snapshots=snapshots,
            telemetry=samples,
            mean={k: statistics.mean(v[k] for v in samples) for k in samples[0]},
            probe_exit=proc.returncode if proc else None,
        )


parser = argparse.ArgumentParser()
for arg in ("meter", "app", "weights", "wav", "out", "panels"):
    parser.add_argument("--" + arg, type=Path, required=True)
a = parser.parse_args()
meta = plistlib.loads((a.app / "Contents/Info.plist").read_bytes())
row = next(
    x for x in json.loads(a.panels.read_text())["samples"] if x["duration"] >= 10
)
source = a.wav / (row["id"] + ".wav")
assert hashlib.sha256(source.read_bytes()).hexdigest() == row["audio_sha256"]
a.out.mkdir(exist_ok=True)
for model in ("apple", "sherpa", "qwen-small", "zipformer"):
    dest = a.out / (model + ".json")
    if dest.exists():
        raise FileExistsError(dest)
    if any(
        ids("-x", name)
        for name in ("SaytileSherpa", "SaytileModelWorker", "MandarinCohort", "Cohort")
    ):
        raise RuntimeError("concurrent inference before power pair")
    with tempfile.TemporaryDirectory(prefix="saytile-mandarin-resource-") as name:
        tmp = Path(name)
        shutil.copyfile(source, tmp / "fixture.wav")
        if model != "apple":
            (tmp / "LocalModels").mkdir()
            sp.run(["cp", "-cR", a.weights / model, tmp / "LocalModels"], check=True)
        idle = measure("idle", a.meter, lambda: None)
        active = measure(
            "active",
            a.meter,
            lambda: sp.Popen(
                [
                    a.app / "Contents/MacOS/Saytile",
                    "--data-directory",
                    tmp,
                    "--local-stream-probe",
                    model,
                ],
                stdout=sp.DEVNULL,
                stderr=sp.DEVNULL,
            ),
        )
        panel = json.loads((tmp / "visible.json").read_text())
        assert panel["providers"] == [
            "apple-speech-analyzer" if model == "apple" else model
        ]
        dest.write_text(
            json.dumps(
                dict(
                    source=meta["SaytileSourceRevision"],
                    model=model,
                    wave=row["audio_sha256"],
                    idle=idle,
                    active=active,
                    window_updates=panel["displayedChanges"],
                ),
                separators=(",", ":"),
            )
            + "\n"
        )
