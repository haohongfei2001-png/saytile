# no-api.9 local verification

The procedures are prepared for the neutral-material release candidate. They use the committed Tingting test asset bound by `input-fixture.json`, the frozen Git revision/tree supplied by the release owner, and `/tmp/saytile-no-api9-<revision-prefix>` for this version's executables and reference. The Store recovery, capacity and VAD checks run before the independent conversion reference. The 1,800-second driver and the existing 23-condition assessment run after the designated freeze and start instruction.

```sh
python3 evidence/no-api9/local/run-short-evidence.py > evidence/no-api9/local/short-driver.log 2>&1
python3 evidence/no-api9/local/run-realtime-evidence.py > evidence/no-api9/local/realtime-monitor.log 2>&1
python3 evidence/no-api9/local/finalize-realtime-evidence.py > evidence/no-api9/local/realtime-assessment.log 2>&1
```
