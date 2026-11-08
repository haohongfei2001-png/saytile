#!/usr/bin/env python3
"""Real background NSTextView AX acceptance. Never prompts, activates, or grants TCC.

Exit 0: real AX pass (or explicitly compile-only); 5: BLOCKED; 1: FAIL.
All build/cache/database/log files live in one fresh private /tmp directory.
No existing native test scripts, app preferences or production archives are used.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


class Blocked(Exception):
    pass


def run(args):
    scratch = Path(tempfile.mkdtemp(prefix="saytile-owned-range-native-", dir="/tmp")).resolve()
    print(f"SCRATCH {scratch}", flush=True)
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(scratch / "clang-cache"),
               SWIFTPM_MODULECACHE_OVERRIDE=str(scratch / "swift-cache"))
    summary = {"status": "NOT_RUN", "compile": "NOT_RUN", "native_ax": "NOT_RUN",
               "scratch": str(scratch), "execution_context": args.execution_context,
               "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "scope": "production coordinator + Store + AXInputAccess; injected own fixture selection",
               "scenarios_planned": 9, "scenarios_passed": [],
               "tcc_prompt": False, "foreground_resolver": "NOT_RUN"}
    children = []
    log = (scratch / "probe.log").open("w")

    def record(line):
        log.write(line + "\n"); log.flush()
        print(line, flush=True)

    def command(argv, filename, timeout=240):
        with (scratch / filename).open("w") as output:
            try:
                result = subprocess.run(argv, cwd=ROOT, env=env, stdout=output,
                                        stderr=subprocess.STDOUT, timeout=timeout)
            except subprocess.TimeoutExpired as error:
                raise Blocked(f"BUILD_TIMEOUT_NO_RETRY: see {filename}") from error
        if result.returncode:
            detail = (scratch / filename).read_text(errors="replace")
            if any(marker in detail for marker in ["Operation not permitted", "sandbox-exec:", "Permission denied"]):
                raise Blocked(f"BUILD_SANDBOX_OR_PERMISSION: see {filename}")
            raise RuntimeError(f"build exit {result.returncode}: see {filename}")

    messages = queue.Queue(maxsize=1024)

    def spawn(argv, name):
        process = subprocess.Popen(argv, cwd=scratch, env=env, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        children.append(process)

        def pump():
            for line in process.stdout:
                if len(line) > 16384:
                    messages.put((name, "OVERSIZED_OUTPUT")); return
                messages.put((name, line.rstrip("\n")))
            messages.put((name, None))
        threading.Thread(target=pump, daemon=True).start()
        return process

    try:
        summary["head"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        paths = ["tests/fixtures/OwnedRangeNativeProbe.swift", "tests/fixtures/OwnedRangeNativeTextFixture.swift",
                 "tests/fixtures/AXFixtureActivationAudit.swift", "scripts/test-owned-range-native.py"]
        paths += [str(p.relative_to(ROOT)) for p in sorted((ROOT / "Sources").rglob("*")) if p.is_file()]
        summary["source_sha256"] = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
        def verify_sources_unchanged():
            changed = [p for p, digest in summary["source_sha256"].items()
                       if not (ROOT / p).exists() or hashlib.sha256((ROOT / p).read_bytes()).hexdigest() != digest]
            summary["source_changed_during_run"] = changed
            if changed:
                raise RuntimeError("source changed during acceptance; rerun only after source freeze")
        command(["swiftc", "-swift-version", "6", "-parse-as-library",
                 str(ROOT / "tests/fixtures/OwnedRangeNativeTextFixture.swift"),
                 "-module-cache-path", str(scratch / "clang-cache"),
                 "-o", str(scratch / "OwnedRangeNativeTextFixture")], "compile-fixture.log")
        # Build current production sources directly. This does not execute a SwiftPM
        # manifest (nested sandbox creation is unavailable in some agent sandboxes).
        # No sandbox/TCC controls are changed. C inputs match Package.swift exclusions.
        binary = scratch / "production"
        binary.mkdir()
        module_map = binary / "CAudio.modulemap"
        header = ROOT / "Sources/CAudio/include/SaytileAudio.h"
        module_map.write_text('module CAudio { header ' + json.dumps(str(header)) + ' export * }\n')
        objects = []
        audio = ROOT / "Sources/CAudio"
        c_sources = sorted(audio.rglob("*.c")) + sorted(audio.rglob("*.cc"))
        for index, source in enumerate(c_sources):
            if source.name == "dot_product_with_scale.cc":
                continue  # Same explicit exclusion as the production package.
            obj = binary / f"audio-{index}.o"
            command(["clang++" if source.suffix == ".cc" else "clang", "-c", str(source),
                     "-I", str(audio), "-I", str(audio / "include"), "-DWEBRTC_POSIX",
                     *(["-std=c++17"] if source.suffix == ".cc" else []), "-o", str(obj)], f"compile-audio-{index}.log")
            objects.append(str(obj))
        sources = sorted((ROOT / "Sources/SaytileKit").glob("*.swift"))
        command(["swiftc", "-swift-version", "6", "-parse-as-library", "-enable-testing",
                 "-module-name", "SaytileKit", "-emit-library", "-static", "-emit-module",
                 "-emit-module-path", str(binary / "SaytileKit.swiftmodule"),
                 "-I", str(ROOT / "Sources/CSQLite"), "-Xcc", "-fmodule-map-file=" + str(module_map),
                 "-module-cache-path", str(scratch / "clang-cache"),
                 *map(str, sources), *objects, "-lc++", "-o", str(binary / "libSaytileKit.a")],
                "build-production.log", timeout=600)
        probe = scratch / "OwnedRangeNativeProbe"
        command(["swiftc", "-swift-version", "6", "-parse-as-library", "-I", str(ROOT / "Sources/CSQLite"),
                 "-I", str(binary), "-I", str(binary / "Modules"),
                 "-Xcc", "-fmodule-map-file=" + str(module_map), "-L", str(binary), "-lSaytileKit", "-lc++",
                 "-module-cache-path", str(scratch / "clang-cache"),
                 str(ROOT / "tests/fixtures/AXFixtureActivationAudit.swift"),
                 str(ROOT / "tests/fixtures/OwnedRangeNativeProbe.swift"), "-o", str(probe)], "compile-probe.log")
        summary["compile"] = "PASS"
        summary["binary_sha256"] = {str(p.relative_to(scratch)): hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in [probe, scratch / "OwnedRangeNativeTextFixture", binary / "libSaytileKit.a"]}
        verify_sources_unchanged()
        if args.compile_only:
            summary["status"] = "COMPILE_ONLY_PASS"
            record("COMPILE_ONLY_PASS native_AX=NOT_RUN")
            return 0
        # No fixture is launched when this same executable lacks existing AX trust.
        preflight = subprocess.run([str(probe), "--preflight"], cwd=scratch, env=env,
                                   capture_output=True, text=True, timeout=10)
        (scratch / "preflight.log").write_text(preflight.stdout + preflight.stderr)
        if preflight.returncode:
            raise Blocked("AX_PREFLIGHT_UNAVAILABLE_NO_PROMPT; see preflight.log")
        nonce = str(uuid.uuid4())
        fixture = spawn([str(scratch / "OwnedRangeNativeTextFixture"), nonce], "fixture")

        def reply(line, command_name):
            value = json.loads(line)
            if value.get("pid") != fixture.pid or value.get("nonce") != nonce or value.get("command") != command_name:
                raise RuntimeError("fixture IPC identity/command mismatch")
            if value.get("keyWindow") is not False or value.get("mainWindow") is not False or value.get("keyboardEvents") != 0:
                raise RuntimeError("Background fixture keyboard isolation failed; no keyboard characters recorded")
            if not all(value.get(field, {}).get("knownSyntheticText") is True for field in ["primary", "alternate"]):
                raise RuntimeError("Unexpected fixture text; omitted from evidence")
            return value

        deadline = time.monotonic() + 10
        while True:
            try:
                source, line = messages.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                raise Blocked("FIXTURE_STARTUP_UNAVAILABLE_NO_ACTIVATION")
            if source == "fixture" and line and line.startswith("{"):
                reply(line, "ready"); break
            if line is None or time.monotonic() >= deadline:
                raise Blocked("FIXTURE_STARTUP_UNAVAILABLE_NO_ACTIVATION")
            # Preserve bounded diagnostics without writing arbitrary fixture text to console.
            log.write("FIXTURE_STARTUP " + line + "\n")
        record(f"FIXTURE_READY exact_spawned_pid={fixture.pid} nonce_verified=true")
        worker = spawn([str(probe), str(fixture.pid), nonce, str(scratch)], "probe")
        deadline, pending, passed, eof = time.monotonic() + 45, None, False, False
        allowed = {"reset", "state", "manual-edit", "select", "reject-replacement", "focus-alternate", "close-window"}
        while time.monotonic() < deadline and not eof:
            try:
                source, line = messages.get(timeout=0.1)
            except queue.Empty:
                continue
            if source == "probe":
                if line is None:
                    eof = True; continue
                record(line)
                if line.startswith("PASS ") and " real_AX=true " in line:
                    summary["scenarios_passed"].append(line.split()[1])
                if line.startswith("FIXTURE_RPC "):
                    cmd = line.removeprefix("FIXTURE_RPC ")
                    if cmd not in allowed or pending is not None:
                        raise RuntimeError("unexpected fixture RPC")
                    pending = cmd
                    fixture.stdin.write(json.dumps({"command": cmd, "nonce": nonce}) + "\n"); fixture.stdin.flush()
                if line.startswith("OWNED_RANGE_NATIVE_PASS "):
                    passed = True
            elif line and line.startswith("{"):
                if pending is None:
                    raise RuntimeError("unsolicited fixture reply")
                reply(line, pending)
                # Only the probe receives synthetic text; console/log record counts and verdicts.
                worker.stdin.write(line + "\n"); worker.stdin.flush()
                pending = None
            elif line is None:
                raise RuntimeError("fixture exited during acceptance")
            else:
                log.write("FIXTURE_DIAGNOSTIC " + line + "\n")
        if not eof:
            raise RuntimeError("probe deadline exceeded; no retry")
        code = worker.wait(timeout=3)
        if code == 5:
            raise Blocked("REAL_AX_UNAVAILABLE; see probe.log")
        if code != 0 or not passed or pending is not None or len(summary["scenarios_passed"]) != summary["scenarios_planned"]:
            raise RuntimeError(f"probe failed exit={code}; no mutation retry")
        verify_sources_unchanged()
        summary["native_ax"] = "PASS"
        summary["status"] = "PASS"
        return 0
    except Blocked as error:
        summary.update(status="BLOCKED", reason=str(error))
        if summary["compile"] == "PASS":
            summary["native_ax"] = "BLOCKED"
        else:
            summary["compile"] = "BLOCKED"
        record("BLOCKED " + str(error))
        return 5
    except (Exception, KeyboardInterrupt) as error:
        summary.update(status="FAIL", reason=str(error))
        if summary["compile"] != "PASS":
            summary["compile"] = "FAIL"
        if summary["compile"] == "PASS" and not args.compile_only:
            summary["native_ax"] = "FAIL"
        record("FAIL " + str(error))
        return 1
    finally:
        for child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    child.kill(); child.wait()
        summary["finished_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (scratch / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
        log.close()
        print(f"EVIDENCE {scratch / 'summary.json'}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compile-only", action="store_true", help="Compile both binaries without AX or fixture launch")
    parser.add_argument("--execution-context", choices=["sandbox", "unsandboxed", "unspecified"], default="unspecified",
                        help="Evidence label only; never changes sandbox or permissions")
    sys.exit(run(parser.parse_args()))
