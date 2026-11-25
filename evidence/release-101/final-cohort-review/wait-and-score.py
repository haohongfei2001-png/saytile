"""Bounded 15-second read-only wait; score only after both complete quality exits."""
from pathlib import Path
import datetime, hashlib, json, subprocess, time
R = Path("/private/tmp/saytile-release-101")
OUT = Path(__file__).resolve().parent
OWN = Path("/private/tmp/saytile-101-input")
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
deadline = time.monotonic() + 5400
checks = 0
while time.monotonic() < deadline:
    checks += 1
    try:
        events = json.loads((R / "evidence/release-101/regression-final/progress.json").read_bytes())
    except (OSError, ValueError):
        time.sleep(15)
        continue
    arms = {e["arm"]: e for e in events if e.get("phase") == "quality" and e.get("arm") in ("baseline", "candidate")}
    if any(e.get("status") == "FAIL" for e in arms.values()):
        outcome = {"status": "BLOCKED", "reason": "quality process failed; no partial scoring", "arms": arms}
        break
    if all(arms.get(k, {}).get("status") == "PASS" and arms[k].get("exit_code") == 0 for k in ("baseline", "candidate")):
        command = ["python3", str(OWN / "scripts/mandarin/report-realtime-cohort.py"),
            "--root", str(R / "evidence/release-101/regression-final"),
            "--manifest", str(R / "evidence/release-101/setup/input440.json"),
            "--manifest-sha256", "f275794d4a14d8e8dae5732deda2f50d5653583a32be27c921d66ac9b0e753c8",
            "--fixture", str(R / "tests/fixtures/MandarinCohort.swift"),
            "--audio", "/private/tmp/saytile-beta-021-20261123/.build/mandarin/wav",
            "--out", str(OUT / "quality-comparison-complete.json")]
        with (OUT / "scorer.log").open("x") as log:
            result = subprocess.run(command, cwd=OWN, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        outcome = {"status": "PASS" if result.returncode == 0 else "FAIL", "exit_code": result.returncode,
                   "command": command, "arms": arms, "scorer_sha256": hashlib.sha256((OWN / "scripts/mandarin/report-realtime-cohort.py").read_bytes()).hexdigest()}
        break
    time.sleep(15)
else:
    outcome = {"status": "BLOCKED", "reason": "bounded 90-minute wait expired; no partial scoring"}
outcome.update(started_utc=started, finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
               checks=checks, interval_seconds=15, no_asr_started=True, root_evidence_modified=False)
(OUT / "wait-and-score-receipt.json").write_text(json.dumps(outcome, indent=2) + "\n")
print(json.dumps(outcome), flush=True)
