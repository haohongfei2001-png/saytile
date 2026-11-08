# Native input, local recognition and durable failover review

Scope: PR #6 source based on `3cd8ebcbc94e7536ea8d4ccfd4474b72e9fd2b46`, with the working changes described below. These are intermediate component results, not a final release manifest. The final frozen revision must rerun the integrated checks. No microphone, speaker playback, existing user document/database, API credential, paid endpoint or new TCC permission was used. Existing RC1 was not replaced.

## Concrete defect fixed

The newly distinguished `permission`, `regionMismatch` and `rateLimited` provider failures were not observed by `FailoverRecognitionSession`. Consequently they did not hand the durable recording to the local path, and subsequent segments could retry cloud immediately. The regression in `failover-errors-red.log` failed 13 assertions across the existing 8-test failover suite.

`RecognitionFailover.swift` now uses the provider's retry classification: permanent authorization, permission, region, quota, configuration and protocol failures block cloud for the current configuration generation and permit local takeover. Connection failures retain the existing bounded next-segment probe circuit. Rate limiting also permits local takeover, with a minimum 60-second next-probe delay; a concurrent rate limit extends rather than shortens an existing delay. Cancellation and incomplete output do not initiate another recognition attempt. No preferences, cloud consent or credential state is changed by this runtime circuit.

`failover-errors-green.log` contains the first green run (10 tests, 2 suites). `local-range-final.log` is the later component run: **11 tests / 2 suites**, including 6 permanent failure cases and 5 new actual-file/ticket cases. These tests use real Store/journal files and controlled provider/clock dependencies; they do not establish live network or real Apple failover behavior.

## Existing native AX harness extended, not replaced

PR #6 already contained 5 real owned-range AX cases. The same `test-owned-range-native.py` script and production `NativeInputCoordinator` / `AXInputAccess` / Store path now cover **9 real background NSTextView scenarios**:

1. Growing a Store-approved correction and appending only the new suffix.
2. Shortening a correction containing emoji / combining sequences, with exact UTF-16 cursor and suffix checks.
3. Actual local user-edit simulation prevents overwrite.
4. Changed selected range prevents overwrite.
5. Changed injected target/control prevents wrong-target dispatch.
6. An actual selected-text setter refusal remains unverified and is not retried.
7. A real AppKit first-responder change invalidates ownership.
8. A real Store close/reopen converts a reserved correction to unverified, invalidates old binding, and prevents replay.
9. Closing the actual owned NSPanel prevents further writes.

The first actual run passed all 9; see `owned-range-intermediate-summary.json`, `owned-range-intermediate-probe.log`, and `owned-range-run.log`. The probe asserts no full AXValue write, paste/clipboard write, key/Return event or owned process activation. It inspects only the explicitly spawned fixture PID; its target selector remains injected. **Production frontmost target discovery and arbitrary third-party apps are NOT_RUN.** Clipboard change count is checked, never clipboard content; external changes are not attributed to the fixture.

The harness now also compares source hashes after compilation and at completion, and records compiled binary hashes. This extra check was added after the intermediate 9-case pass; the final frozen run is required to validate it. The intermediate result is not retroactively advertised as a frozen-source run.

## Apple framework: actual installed local resources

The existing `test-audio-corpus.sh` / `AudioCorpusProbe` now defaults to installed Apple resources only. It no longer calls asset preparation unconditionally. Missing assets return `LOCAL_SPEECH_UNAVAILABLE` (exit 5); the separate opt-in `SAYTILE_CORPUS_PREPARE=1` remains explicit. A Bash 3 empty-array issue and an async-expression compile error encountered while updating the fixture were fixed; the initial failed build logs remain beside the result.

The actual Apple SpeechAnalyzer recognized all **8 synthetic Mandarin files**, generated with macOS `say -o` from the existing committed `MandarinCorpus.json`. All 8 completed through `apple-speech-analyzer` candidates, stored fusion decisions and a dispatchable revision. Each recording produced 21–31 candidate events. The retained `apple-corpus.json` includes full synthetic reference/output, existing normalized CER, critical-phrase misses and timing events.

- First text: 1.211–1.261 seconds; median 1.229 seconds.
- Final completion after input closed: 0.026–0.080 seconds; median 0.038 seconds.
- Per-case normalized CER: 0–0.263. Numeric formatting is not canonicalized; e.g. spoken “三点” versus `3:00` is counted as a difference.
- Actual recognition errors remain visible: `Mac` became `免`, `保存原音` became `保存原因`, `充电器` became `空电视`, and part of `修改开始时间` was wrong.

This proves that the real installed Apple framework feeds the unified candidate/publication path from synthetic files. It **does not** establish human speech quality, live microphone capture, offline handover using actual network failure, cloud provider success, or any dual-ASR/GPT quality gain. No quality threshold was weakened to turn these recognition errors into an accuracy claim.

## Durable range boundary

The existing accelerated 13.44 MB range test remains in use (not a wall-clock soak). New cases mutate disposable actual journal files: truncated header, incompatible format, truncated PCM payload, a symlink to another owned test file, and a retired generation ticket. Every case is rejected; a replacement current ticket still reads the exact PCM. Existing tests also prove that unpublished tail bytes are not returned, deleted audio is unavailable, local results preserve a user edit, and external reserved-prefix conflicts cannot claim successful completion.

The existing `test-rc-storage-processes.py` was reviewed rather than duplicated: it already uses real SIGKILL processes, released Beta/RC1 source, schema-4 preservation assertions, RC1 newer-schema refusal and explicit complete pre-upgrade-copy rollback. The final integration run remains owned by the release coordinator.

## Reproducible commands

Run from the repository root, without changing permissions or touching existing applications:

```bash
SAYTILE_TEST_SCRATCH=/tmp/saytile-no-api-local-tests \
SAYTILE_TEST_LOG=evidence/no-api-product/local-input/local-range-final.log \
scripts/test-native.sh --filter 'OfflineFailoverTests|JournalRangeAndLocalIngressTests'

python3 scripts/test-owned-range-native.py --execution-context unsandboxed

SAYTILE_CORPUS_BUILD=/tmp/saytile-no-api-apple scripts/test-audio-corpus.sh \
  > evidence/no-api-product/local-input/apple-corpus.json \
  2> evidence/no-api-product/local-input/apple-corpus.log
```

The `--execution-context` value is only an evidence label, not a sandbox/TCC bypass. The AX script prints its owned temporary summary path; copy that summary and probe log to the final evidence directory. Do not overwrite the intermediate/red evidence when running the frozen final revision.
