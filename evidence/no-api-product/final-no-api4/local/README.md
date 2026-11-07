# Local verification — no-api.4 / a6849128

Frozen runtime: `a6849128e12e88560daa52fce48f6f2d805a88aa`, tree `5ab4abea901e1d880abadbe4b4b673ca939f076d`.

Status: **INTENTIONALLY_STOPPED_FOR_SOURCE_FIX**. Root revoked the source freeze after an independently confirmed Swift 6.3.3 UIReview trailing-closure issue and an AX fixture caret transition under investigation. On explicit instruction, only owned capture PID 66541 received SIGTERM after 536.05 seconds. The original `source-after.json` records runner exit 143 and `status: FAIL` from the generic runner; it is retained unchanged. This is an intentional partial stop, **not an audio defect and not a 30-minute pass**. See `INTENTIONALLY_STOPPED_FOR_SOURCE_FIX.json`. The complete-waveform final assessor was not run against the interrupted stream.

All audio is the previously committed synthetic Tingting AIFF bound by `input-fixture.json`; no microphone, environmental conversation, speaker output, user archive, live cloud request, private preference or system permission change is involved. Original `evidence/no-api-product/final/` receipts remain unchanged.

The evidence-local runner and assessor are copies of the existing proven final/local recipes, with only new source identity, scratch/output paths and the committed fixture path. The completed assessment additionally asserts that HEAD stayed at the frozen revision. Runtime/test/script/packaging sources are unchanged.

Resource snapshots observe only the owned capture process and disposable database every 45 seconds. No native AX or Apple ASR result from a different source is counted as a result of this run.

| Check | Current result | Evidence |
| --- | --- | --- |
| VAD buffer allocation | PASS; 66.7 MB synthetic input, incremental peak RSS 245,760 bytes | `voice-buffer.json` |
| Storage scale | PASS; 100,000 recordings / 300,000 revisions at schema 5 | `storage-scale/storage-scale.json` |
| Process recovery, migration and rollback | 12 checks PASS; real SIGKILL, released Beta/RC1 migration, zero implicit upload grants, RC1 refusal and complete backup restore | `storage-processes.json` |
| Independent conversion reference | PASS; 39,690,000 input frames all supplied in 4,845 batches, 28,800,000 output frames | `conversion-reference.json` |
| 30-minute capture and complete saved waveform | INTENTIONALLY STOPPED after 536.05s for source fix; final assessor not run | `INTENTIONALLY_STOPPED_FOR_SOURCE_FIX.json`, original run/resources/source receipts |

`probe-binaries.json` binds all current test executables, including the historical released-store probes. Those historical baselines are deliberately retained for migration checks; they are not presented as current runtime binaries.

## Reproduction and limits

The committed source AIFF has SHA256 `d7deb6ef7c7a6cc330fbb4ee82eb2733f82ee7761634e6df55f650037bf0b751`, 125,714 bytes, 60,809 frames at 22,050 Hz. Its original exact `say` command/rate was not retained. The committed file permits byte-identical replay; its speech is not an ASR ground truth here. The repeated 30-minute outputs remain in disposable storage and are not committed.

Commands run from the repository root, with separate output and scratch paths to preserve the earlier receipts:

```sh
python3 evidence/no-api-product/final-no-api4/local/run-realtime-evidence.py
SAYTILE_BUFFER_SCRATCH=/tmp/saytile-final-a6849128-static scripts/test-audio-buffer-memory.sh
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-a6849128-static python3 scripts/test-rc-storage-processes.py --output evidence/no-api-product/final-no-api4/local/storage-processes.json
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-a6849128-static SAYTILE_STORAGE_OUTPUT=evidence/no-api-product/final-no-api4/local/storage-scale scripts/test-rc-storage-scale.sh
bash evidence/no-api-product/final-no-api4/local/run-conversion-reference.sh
# Only after the complete capture process exits:
python3 evidence/no-api-product/final-no-api4/local/finalize-realtime-evidence.py
```

Resource probes link the complete frozen SwiftPM debug SaytileKit. Their optimized fixture executables are not packaged Release-app energy benchmarks. The VAD allocation test is accelerated rather than a soak. The scale check uses real SQLite FULL writes and Store queries on synthetic metadata; it excludes bulk audio deletion and UI. Process rollback uses a stopped complete disposable backup and leaves both upgraded and restored fixtures distinguishable. No successful cloud call, human accuracy, physical device transition, external foreground insertion or 24/72-hour endurance result is inferred.

The full-waveform assessor verifies every WAV payload, chronological recording/chunk order, all reference bytes consumed, total frames, header/SQLite consistency, zero implicit upload grants, zero ring overflow, actual process duration, and input/source/executable hashes. A normal process exit, plausible duration or internally consistent database alone cannot pass it.
