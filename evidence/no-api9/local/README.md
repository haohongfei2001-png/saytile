# no-api.9 neutral release-candidate local verification

Frozen neutral-material runtime `dc26fe3c59ba55994d29e99ada8d2f0b49ad9886`, tree `f138f6733a642a2e53da22b3647aaf5744cb308b`, passed all eight short checks. Its single 30-minute capture started at 12:53:10 China Standard Time on 2026-11-07 under PID 5504. The full waveform assessment follows natural exit. The committed Tingting synthetic input is bound by `input-fixture.json`. Scratch paths use `/tmp/saytile-no-api9-dc26fe3c59ba`, and the owned database is `/tmp/saytile-rc-realtime-data.UcZxPa`.

Store passed all 12 process recovery, migration and rollback checks. The test archive contained 100,000 recordings and 300,000 revisions. Partial writes took 0.234 ms p95, and the 100 expected search results took 165.762 ms. VAD processed 66.7 MB with a peak RSS increase of 245,760 bytes. The independent converter accepted all 4,845 batches and produced 28,800,000 frames, including 1,494 drained tail frames. Its reference SHA-256 is `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`.

The checks used these frozen identifiers.

```sh
export SAYTILE_FROZEN_SHA=dc26fe3c59ba55994d29e99ada8d2f0b49ad9886
export SAYTILE_FROZEN_TREE=f138f6733a642a2e53da22b3647aaf5744cb308b
python3 evidence/no-api9/local/run-short-evidence.py > evidence/no-api9/local/short-driver.log 2>&1
python3 evidence/no-api9/local/run-realtime-evidence.py > evidence/no-api9/local/realtime-monitor.log 2>&1
python3 evidence/no-api9/local/finalize-realtime-evidence.py > evidence/no-api9/local/realtime-assessment.log 2>&1
```
