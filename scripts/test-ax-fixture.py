#!/usr/bin/env python3
"""Real AX primitives against a synthetic activation-prohibited NSTextView only.

Never prompts for Accessibility or microphone permission, never touches another app's
content, and leaves no running fixture. This does not certify Saytile's TCC identity,
frontmost-target binding, browser SPA navigation, or Cmd+V fallback.
"""
from pathlib import Path
import json
import select
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="saytile-ax-fixture-") as temporary:
    folder = Path(temporary)
    fixture_binary, probe_binary = folder / "fixture", folder / "probe"
    for source, binary in [("AXTextFixture.swift", fixture_binary), ("AXFixtureProbe.swift", probe_binary)]:
        subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library", str(ROOT / "tests/fixtures" / source), "-o", str(binary)], check=True)
    fixture = subprocess.Popen([str(fixture_binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        if not select.select([fixture.stdout], [], [], 5)[0]:
            raise RuntimeError("Fixture did not start within five seconds")
        assert fixture.stdout.readline().strip() == "FIXTURE_READY"
        result = subprocess.run([str(probe_binary), str(fixture.pid)], capture_output=True, text=True, timeout=10)
        print(result.stdout, end="")
        report = {
            "scope": "Synthetic activation-prohibited NSTextView; AX primitives, not production TCC or browser acceptance",
            "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr,
            "microphone_used": False, "user_apps_accessed": False,
        }
        (ROOT / "evidence/native-ax-fixture-latest.json").write_text(json.dumps(report, indent=2) + "\n")
    finally:
        fixture.terminate()
        try:
            fixture.wait(timeout=3)
        except subprocess.TimeoutExpired:
            fixture.kill()
            fixture.wait()
    raise SystemExit(result.returncode)
