# no-api.8 release-candidate local verification

Frozen release runtime `69b90939fd688b35448f976950e96db0ce5b602a`, tree `06f1ac6982591bce64c98bd93e26eb0ccba0cfd8`, passed all eight short checks. Its single 30-minute capture started at 12:31:18 China Standard Time on 2026-11-07 under PID 67475. The full waveform assessment follows natural exit. The committed Tingting synthetic input is bound by `input-fixture.json`. Scratch paths use `/tmp/saytile-no-api8-69b90939fd68`, and the owned database is `/tmp/saytile-rc-realtime-data.HLK7GZ`.

Store passed all 12 process recovery, migration and rollback checks. The synthetic archive contained 100,000 recordings and 300,000 revisions. Partial writes took 0.168 ms p95, and the 100 expected search results took 140.692 ms. VAD processed 66.7 MB with a peak RSS increase of 229,376 bytes. The independent converter accepted all 4,845 batches and produced 28,800,000 frames, including 1,494 drained tail frames. Its reference SHA-256 is `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`.

The checks used these frozen identifiers.

```sh
export SAYTILE_FROZEN_SHA=69b90939fd688b35448f976950e96db0ce5b602a
export SAYTILE_FROZEN_TREE=06f1ac6982591bce64c98bd93e26eb0ccba0cfd8
python3 evidence/no-api8/local/run-short-evidence.py > evidence/no-api8/local/short-driver.log 2>&1
python3 evidence/no-api8/local/run-realtime-evidence.py > evidence/no-api8/local/realtime-monitor.log 2>&1
python3 evidence/no-api8/local/finalize-realtime-evidence.py > evidence/no-api8/local/realtime-assessment.log 2>&1
```
