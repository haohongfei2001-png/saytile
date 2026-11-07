# no-api.8 local verification

The storage, VAD, conversion reference, wall-clock driver and final assessment recipes are prepared for the frozen no-api.8 runtime. They use the committed synthetic Tingting input bound by `input-fixture.json` and dedicated `/tmp/saytile-no-api8-<revision-prefix>` scratch paths. Resource samples observe the owned capture process and its disposable SQLite database at 45-second intervals.

Set `SAYTILE_FROZEN_SHA` and `SAYTILE_FROZEN_TREE` to the assigned full Git identifiers. Run the existing short checks, then one 1,800-second capture. After the process exits naturally, run the 23-condition assessor once to compare every saved WAV payload against the complete independent PCM reference.

```sh
python3 evidence/no-api8/local/run-short-evidence.py > evidence/no-api8/local/short-driver.log 2>&1
python3 evidence/no-api8/local/run-realtime-evidence.py > evidence/no-api8/local/realtime-monitor.log 2>&1
python3 evidence/no-api8/local/finalize-realtime-evidence.py > evidence/no-api8/local/realtime-assessment.log 2>&1
```
