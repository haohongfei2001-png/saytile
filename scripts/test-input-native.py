#!/usr/bin/env python3
"""Production coordinator + SQLite + AX against owned invisible fixtures.

Default tests inject target selection. The optional foreground batch uses the real
production resolver with a fixture PID guard and aborts before activation if the
session is busy. Neither mode certifies all third-party browsers or app TCC identity. No prompts.
"""
from pathlib import Path
import argparse
import json
import os
import queue
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
SCRATCH = Path(os.environ.get("SAYTILE_INPUT_SCRATCH", "/tmp/saytile-rc-input"))
SCRATCH.mkdir(parents=True, exist_ok=True)
EVIDENCE = ROOT / "evidence/rc"
EVIDENCE.mkdir(parents=True, exist_ok=True)
production = [ROOT / "Sources/SaytileKit/Models.swift", *sorted((ROOT / "Sources/SaytileKit").glob("Store*.swift")), *sorted((ROOT / "Sources/SaytileKit").glob("Input*.swift"))]

def compile_source(source, binary, production_sources=False):
    subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library", "-I", str(ROOT / "Sources/CSQLite"), *map(str, production if production_sources else []), str(ROOT / "tests/fixtures" / source), "-o", str(binary)], check=True)

def lines_to_queue(stream, name, messages):
    for line in stream:
        messages.put((name, line))

def run_fixture(fixture_name, probe_name, log_name, ready, web=False):
    fixture_bin, probe_bin = SCRATCH / fixture_name, SCRATCH / probe_name
    compile_source(fixture_name + ".swift", fixture_bin)
    compile_source(probe_name + ".swift", probe_bin, True)
    messages = queue.Queue()
    output = []
    def record(line):
        output.append(line); print(line, end="", flush=True)
    fixture = subprocess.Popen([str(fixture_bin)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    threading.Thread(target=lines_to_queue, args=(fixture.stdout, "fixture", messages), daemon=True).start()
    probe = None
    try:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            name, line = messages.get(timeout=max(0.01, deadline-time.monotonic()))
            record(line)
            if line.strip() == ready: break
        else: raise RuntimeError("Fixture startup timed out")
        probe = subprocess.Popen([str(probe_bin), str(fixture.pid)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        threading.Thread(target=lines_to_queue, args=(probe.stdout, "probe", messages), daemon=True).start()
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline and (probe.poll() is None or not messages.empty()):
            try: name, line = messages.get(timeout=0.2)
            except queue.Empty: continue
            record(line)
            if line.startswith("FIXTURE_COMMAND "):
                fixture.stdin.write(json.dumps({"command": line.strip().split(" ", 1)[1]}) + "\n"); fixture.stdin.flush()
        if probe.poll() is None: raise RuntimeError("Probe timed out")
        if probe.returncode: raise RuntimeError(f"Probe exit {probe.returncode}; no permission prompts or focus escalation attempted")
        if web:
            fixture.stdin.write('{"command":"state"}\n'); fixture.stdin.flush()
            deadline=time.monotonic()+3
            while time.monotonic()<deadline:
                name,line=messages.get(timeout=max(0.01,deadline-time.monotonic()))
                record(line)
                if name=="fixture" and line.startswith('{'):
                    state=json.loads(line)
                    if state.get("command")=="state":
                        assert json.loads(state["value"])["sends"] == 0, "Web fixture sent a message"
                        record("PASS real WKWebView fixture never sends\n")
                        break
            else: raise RuntimeError("Missing web state")
    finally:
        if probe and probe.poll() is None: probe.kill(); probe.wait()
        fixture.terminate()
        try: fixture.wait(timeout=3)
        except subprocess.TimeoutExpired: fixture.kill(); fixture.wait()
        (EVIDENCE / log_name).write_text("".join(output))

def foreground_batch(compile_only=False):
    # These binaries remain prohibited until the probe explicitly passes preflight.
    for source, include_production in [("AXTextFixture", False), ("AXWebFixture", False), ("AXForegroundBatchProbe", True)]:
        compile_source(source + ".swift", SCRATCH / source, include_production)
    if compile_only:
        print("FOREGROUND_COMPILE_ONLY_PASS; no fixtures or foreground probe executed")
        return
    if os.environ.get("SAYTILE_ALLOW_FOREGROUND_INPUT_FIXTURES") != "1":
        raise SystemExit("NOT_RUN: set SAYTILE_ALLOW_FOREGROUND_INPUT_FIXTURES=1 for the explicit foreground batch")
    fixtures = {}; messages = queue.Queue(); output = []; probe = None
    def record(line):
        output.append(line); print(line, end="", flush=True)
    try:
        for kind, name, ready in [("native", "AXTextFixture", "FIXTURE_READY"), ("web", "AXWebFixture", "WEB_FIXTURE_READY")]:
            fixture = subprocess.Popen([str(SCRATCH / name), "--foreground-armed"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
            fixtures[kind] = fixture
            threading.Thread(target=lines_to_queue, args=(fixture.stdout, kind, messages), daemon=True).start()
            deadline = time.monotonic() + 10
            while True:
                source, line = messages.get(timeout=max(0.01, deadline - time.monotonic()))
                record(line)
                if source == kind and line.strip() == ready: break
                if time.monotonic() >= deadline: raise RuntimeError("Fixture startup timed out without activation")
        probe = subprocess.Popen([str(SCRATCH / "AXForegroundBatchProbe"), "--allow-foreground", str(fixtures["native"].pid), str(fixtures["web"].pid)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        threading.Thread(target=lines_to_queue, args=(probe.stdout, "probe", messages), daemon=True).start()
        deadline = time.monotonic() + 30
        pending = None
        while time.monotonic() < deadline and (probe.poll() is None or not messages.empty()):
            try: source, line = messages.get(timeout=0.1)
            except queue.Empty: continue
            # Never log fixture text; a user could type into the owned field just
            # before the age monitor aborts. The probe compares only fixed synthetic expectations.
            if source in fixtures and line.startswith("{"):
                summary = json.loads(line)
                record(f"FIXTURE_REPLY {source} command={summary.get('command')} error={bool(summary.get('error'))} value_omitted=true\n")
            else:
                record(line)
            if source == "probe" and line.startswith("FIXTURE_RPC "):
                request = json.loads(line.removeprefix("FIXTURE_RPC "))
                kind, command = request["target"], request["command"]
                if kind not in fixtures or pending is not None: raise RuntimeError("Unexpected fixture IPC")
                pending = (kind, command)
                fixtures[kind].stdin.write(json.dumps({"command": command}) + "\n"); fixtures[kind].stdin.flush()
            elif source in fixtures and line.startswith("{"):
                response = json.loads(line)
                if pending == (source, response.get("command")):
                    if probe.poll() is None:
                        probe.stdin.write(json.dumps(response) + "\n"); probe.stdin.flush()
                    pending = None
        if probe.poll() is None: raise RuntimeError("Foreground batch exceeded 30 seconds; terminating owned fixtures without reactivation")
        if probe.returncode: raise RuntimeError(f"Foreground batch exit {probe.returncode}; no retry or focus reacquisition")
    finally:
        if probe and probe.poll() is None: probe.kill(); probe.wait()
        # Closing owned fixtures lets macOS choose focus. Never explicitly restore on
        # activity/foreign focus interruption; the Swift probe restores only safe completion.
        for fixture in fixtures.values():
            fixture.terminate()
            try: fixture.wait(timeout=3)
            except subprocess.TimeoutExpired: fixture.kill(); fixture.wait()
        (EVIDENCE / "input-foreground-batch.log").write_text("".join(output))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--foreground-batch", action="store_true", help="Explicit opt-in; existing AX permission and >=60s keyboard/mouse idle required; aborts on activity")
    mode.add_argument("--compile-foreground-only", action="store_true", help="Compile opt-in fixtures/probe, without running or activating anything")
    args = parser.parse_args()
    if args.foreground_batch or args.compile_foreground_only:
        foreground_batch(compile_only=args.compile_foreground_only)
    else:
        run_fixture("AXTextFixture", "AXCoordinatorProbe", "input-native-coordinator.log", "FIXTURE_READY")
        run_fixture("AXWebFixture", "AXWebCoordinatorProbe", "input-webkit-observer.log", "WEB_FIXTURE_READY", True)
