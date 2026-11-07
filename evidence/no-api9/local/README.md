# no-api.9 neutral release-candidate local verification

Frozen neutral-material runtime `dc26fe3c59ba55994d29e99ada8d2f0b49ad9886`, tree `f138f6733a642a2e53da22b3647aaf5744cb308b`, passed all eight short checks. Its single 30-minute capture started at 12:53:10 China Standard Time on 2026-11-07 under PID 5504. It completed in 1800.41 seconds. The final assessor passed all 23 conditions, with identical saved and reference PCM across 28,800,000 samples. The committed Tingting synthetic input is bound by `input-fixture.json`. Scratch paths use `/tmp/saytile-no-api9-dc26fe3c59ba`, and the owned database is `/tmp/saytile-rc-realtime-data.UcZxPa`.

Store passed all 12 process recovery, migration and rollback checks. The test archive contained 100,000 recordings and 300,000 revisions. Partial writes took 0.234 ms p95, and the 100 expected search results took 165.762 ms. VAD processed 66.7 MB with a peak RSS increase of 245,760 bytes. The independent converter accepted all 4,845 batches and produced 28,800,000 frames, including 1,494 drained tail frames. Its reference SHA-256 is `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`.

The checks used these frozen identifiers.

```sh
export SAYTILE_FROZEN_SHA=dc26fe3c59ba55994d29e99ada8d2f0b49ad9886
export SAYTILE_FROZEN_TREE=f138f6733a642a2e53da22b3647aaf5744cb308b
python3 evidence/no-api9/local/run-short-evidence.py > evidence/no-api9/local/short-driver.log 2>&1
python3 evidence/no-api9/local/run-realtime-evidence.py > evidence/no-api9/local/realtime-monitor.log 2>&1
python3 evidence/no-api9/local/finalize-realtime-evidence.py > evidence/no-api9/local/realtime-assessment.log 2>&1
```

## Complete capture and archive

The producer delivered 39,690,000 source frames. All 60 recordings and 179 WAV chunks finished and remained available. The files occupy 57,607,876 bytes with headers. Every WAV payload was checked in chronological recording/chunk order, with matching headers, SQLite metadata and frame totals. The archive saved 28,800,000 mono 16 kHz samples, exactly 1800 seconds. The float sum in the console is `1799.9999999999977`.

The comparison consumed the full reference. Differing samples were 0. Saved PCM and reference share SHA-256 `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`. SQLite passed integrity checking at schema 5, the ring reported zero dropped frames, and the upload-grant count remained zero. The 60 pending ASR entries are expected in this recognition-disabled capture.

The probe exited naturally with status zero. Frozen HEAD, all 208 source hashes, the synthetic input and all seven recorded executables retained their identities. The 40 resource samples reported RSS of 15,632–17,568 KiB and CPU of 0.4–2.3%. There were 40 read-only database observations and 0 observation errors. Process CPU totaled 17.11 seconds user plus 10.82 seconds system, or 1.551% of one CPU across the capture. Peak RSS was 18,776,064 bytes and peak physical footprint was 7,094,992 bytes.

The .8 and .9 synthetic capture processes overlapped for approximately 8 minutes 8 seconds. Each used its own SHA-bound binary, reference, database and receipt directory. Resource values above measure the identified process. The verification covers the production capture and persistence path using a committed synthetic input and SwiftPM debug library. Live cloud recognition, physical-device audio and human speech quality remain separate acceptance scopes.
