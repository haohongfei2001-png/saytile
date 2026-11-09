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
import signal
import shutil
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
SCRATCH = Path(os.environ.get("SAYTILE_INPUT_SCRATCH", "/tmp/saytile-rc-input"))
SCRATCH.mkdir(parents=True, exist_ok=True)
EVIDENCE = Path(os.environ.get("SAYTILE_INPUT_EVIDENCE_DIRECTORY", str(ROOT / "evidence/rc")))
EVIDENCE.mkdir(parents=True, exist_ok=True)
package_flags = None

def production_flags():
    global package_flags
    if package_flags is None:
        command = ["swift", "build", "--product", "SaytileKit", "--scratch-path", str(SCRATCH / "build"), "-Xswiftc", "-enable-testing"]
        subprocess.run(command, cwd=ROOT, check=True)
        binary_directory = Path(subprocess.check_output(command + ["--show-bin-path"], cwd=ROOT, text=True).strip())
        module_map = binary_directory / "../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
        if not module_map.exists(): module_map = binary_directory / "CAudio.build/module.modulemap"
        if not module_map.exists(): raise RuntimeError("CAudio module map missing")
        package_flags = ["-D", "SAYTILE_PACKAGE_PROBE", "-I", str(binary_directory), "-I", str(binary_directory / "Modules"),
                         "-Xcc", "-fmodule-map-file=" + str(module_map), "-L", str(binary_directory), "-lSaytileKit", "-lc++"]
    return package_flags

def compile_source(source, binary, production_sources=False, foreground=False):
    flags = list(production_flags()) if production_sources else []
    if foreground: flags += ["-D", "SAYTILE_FOREGROUND_FIXTURE"]
    fixture_helpers = [str(ROOT / "tests/fixtures/AXFixtureActivationAudit.swift")] if production_sources and source.startswith("AX") else []
    subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library", "-I", str(ROOT / "Sources/CSQLite"),
                    *flags, *fixture_helpers, str(ROOT / "tests/fixtures" / source), "-o", str(binary)], cwd=ROOT, check=True)

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
        startup_isolated = False
        while time.monotonic() < deadline:
            name, line = messages.get(timeout=max(0.01, deadline-time.monotonic()))
            record(line)
            if "ISOLATION_FAILED" in line: raise RuntimeError("Owned fixture startup isolation failed")
            if "FIXTURE_ISOLATION " in line:
                startup_isolated = all(value in line for value in ["initial_expected=true", "key=false", "main=false", "keyboard_events=0"])
            if line.strip() == ready: break
        else: raise RuntimeError("Fixture startup timed out")
        if not startup_isolated: raise RuntimeError("Owned fixture did not establish startup keyboard isolation")
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
        fixture.stdin.write('{"command":"state"}\n'); fixture.stdin.flush()
        deadline=time.monotonic()+3
        while time.monotonic()<deadline:
            name,line=messages.get(timeout=max(0.01,deadline-time.monotonic()))
            record(line)
            if name=="fixture" and line.startswith('{'):
                state=json.loads(line)
                if state.get("command")=="state":
                    value = json.loads(state["value"])
                    isolation = state if web else value
                    assert value["sends"] == 0, "Owned fixture sent a message"
                    assert value["knownSyntheticText"] is True, "Unexpected owned fixture text; omitted from evidence"
                    assert isolation["keyWindow"] is False and isolation["mainWindow"] is False, "Background fixture became key/main"
                    assert isolation["keyboardEvents"] == 0, "Background fixture received keyboard events; characters were not read"
                    record("PASS owned fixture keyboard isolation key=false main=false keyboard_events=0\n")
                    record("PASS real WKWebView fixture never sends\n" if web else "PASS real native fixture never sends\n")
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
        compile_source(source + ".swift", SCRATCH / source, include_production, foreground=True)
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
        probe_started = time.time()
        record(f"PHASE probe_launch native_pid={fixtures['native'].pid} web_pid={fixtures['web'].pid}; synthetic_targets_only=true\n")
        probe = subprocess.Popen([str(SCRATCH / "AXForegroundBatchProbe"), "--allow-foreground", str(fixtures["native"].pid), str(fixtures["web"].pid)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        record(f"PROBE_STARTED pid={probe.pid} executable=AXForegroundBatchProbe\n")
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
        if probe.returncode:
            code = probe.returncode
            signal_name = signal.Signals(-code).name if code < 0 else "none"
            record(f"PROBE_EXIT returncode={code} signal={signal_name}\n")
            reports = sorted([*Path.home().joinpath("Library/Logs/DiagnosticReports").glob("AXForegroundBatchProbe*.crash"),
                              *Path.home().joinpath("Library/Logs/DiagnosticReports").glob("AXForegroundBatchProbe*.ips")],
                             key=lambda path: path.stat().st_mtime if path.exists() else 0)
            recent = [path for path in reports if path.exists() and path.stat().st_mtime >= probe_started - 2]
            if recent:
                report = recent[-1]
                destination = EVIDENCE / ("foreground-crash-report" + report.suffix)
                shutil.copy2(report, destination)
                record(f"CRASH_REPORT_PRESERVED path={destination.name}\n")
            raise RuntimeError(f"Foreground batch exit {code} signal={signal_name}; no retry or focus reacquisition")
        record("PROBE_EXIT returncode=0 signal=none\n")
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
    mode.add_argument("--compile-dom-only", action="store_true", help="Compile the package-linked headless DOM probe, without launching any fixture")
    args = parser.parse_args()
    if args.compile_dom_only:
        compile_source("InputDOMCoordinatorProbe.swift", SCRATCH / "dom-coordinator-probe", True)
    elif args.foreground_batch or args.compile_foreground_only:
        foreground_batch(compile_only=args.compile_foreground_only)
    else:
        run_fixture("AXTextFixture", "AXCoordinatorProbe", "input-native-coordinator.log", "FIXTURE_READY")
        run_fixture("AXWebFixture", "AXWebCoordinatorProbe", "input-webkit-observer.log", "WEB_FIXTURE_READY", True)
