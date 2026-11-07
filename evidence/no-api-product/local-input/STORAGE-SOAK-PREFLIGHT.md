# Storage scale and wall-clock soak preparation

`test-rc-storage-scale.sh` no longer compiles an obsolete four-file subset of Store. It builds the full `SaytileKit` static library with testing visibility and links the existing `StoreScaleProbe`, using the same module-map lookup as `test-rc-storage-processes.py`. The probe explicitly asserts schema 4. The new configurable `SAYTILE_STORAGE_OUTPUT` defaults to `evidence/no-api-product/storage-scale`, so old RC evidence is not overwritten.

The compile-only preflight passed (`storage-scale-compile.log`); no scale runtime result is claimed by that preflight. The existing 100,000-record / 300,000-revision dataset is synthetic metadata. Its cleanup section exercises Store metadata scheduling and concurrent writes; it contains no audio payloads and does not measure bulk real-file deletion throughput.

`AudioRealtimeProbe` was inspected: `exerciseRealtimeFixture` writes at most 1024 source frames per iteration and sleeps against `ContinuousClock` at the exact cumulative sample time. Passing `1800` therefore exercises 30 minutes of elapsed time, not an accelerated hot loop. It covers ring, resampling, VAD, capture worker, journal and SQLite, with recognition explicitly disabled. It does not use microphone or speaker and cannot establish long-running Apple/cloud ASR or real-device behavior. The final result must separately confirm zero dropped frames, no `CAPTURE_FAILURE`, nonempty finished recordings and available saved audio. `/usr/bin/time -l` provides actual wall/user/system time and peak RSS.

Final frozen-source commands, with unique evidence filenames/directories:

```bash
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-no-api-storage \
SAYTILE_STORAGE_OUTPUT=evidence/no-api-product/final/storage-scale \
scripts/test-rc-storage-scale.sh

SAYTILE_STORAGE_SCRATCH=/tmp/saytile-no-api-storage-processes \
python3 scripts/test-rc-storage-processes.py \
  --output evidence/no-api-product/final/storage-processes.json

# Use an explicitly generated synthetic mono AIFF, never a private recording.
SAYTILE_AUDIO_SCRATCH=/tmp/saytile-no-api-realtime \
scripts/test-audio-realtime.sh /tmp/owned-synthetic-fixture.aiff 1800
```

The release coordinator supplies the final source revision before these runs. Storage process testing performs real SIGKILL only on its own child processes and uses actual released Beta/RC1 source against disposable stopped copies; it never opens the user's database or replaces RC1.
