#!/usr/bin/env python3
"""Production coordinator + SQLite + AX against owned invisible fixtures.

Only target selection is injected; real user foreground selection, Saytile's TCC
identity and visible browser insertion are not certified by this test. No prompts.
"""
from pathlib import Path
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

run_fixture("AXTextFixture", "AXCoordinatorProbe", "input-native-coordinator.log", "FIXTURE_READY")
run_fixture("AXWebFixture", "AXWebCoordinatorProbe", "input-webkit-observer.log", "WEB_FIXTURE_READY", True)
