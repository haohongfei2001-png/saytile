# RC2 no-key storage recovery review

Base: `45af67049ddee2553fe1929a812aecb83cc157e4`; changes integrated by the parent agent after this review. Scope: `AudioJournal`, `AudioDiagnostics.recoverAudio`, `Store`, `StoreSQLite`, archive deletion/leases and recovery boundaries. Tests use newly created UUID directories and synthetic PCM only. No production database, private audio, credential or cloud access.

## Reproduced and fixed

1. **Failure transitions were not atomic.** `recordCaptureFailure` and `markAudioMissing` invalidated model runs/fusion sessions before updating the recording. An SQLite trigger aborting that final update left durable cancelled runs and a terminal while the recording remained running. Both transitions now commit all state changes in one transaction. The regression injects the last-statement failure, checks rollback of the runs/session/terminal, removes the fault and verifies successful retry.
2. **Transient recovery failure permanently hid recoverable original audio.** The recovery catch treated any file repair or SQLite reconciliation error as missing audio. A stale WAV header plus real `0400` file permissions reproduced the failure: original bytes remained but the record became missing and could not be recovered later. A separate recovery-failure transition now preserves audio ownership, epoch, chunks and text while recording a clear retryable error. Physical incomplete/oversized files still follow the unavailable-audio path. Only the two known format failures use typed `PCMJournal.RepairFailure`; I/O and SQL failures do not masquerade as physical absence.
3. **Intact read-only audio unnecessarily required write access.** `PCMJournal.repair` previously opened every file for updating before checking its header. It now reads first and requests write access only when a header/tail repair is necessary. A real read-only intact WAV remains readable and unchanged.

4. **One inaccessible recording directory blocked the complete startup recovery.** Independent review identified that `audioURL` validation still ran outside the per-record catch. A real `chmod 000` directory reproduced `.invalidPath` before a healthy older recording could be recovered. Path validation now remains mandatory but occurs inside the per-record catch: the blocked original and draft remain owned, other records recover, and permission restoration plus reopen retries successfully. The boolean `fileExists` precheck was removed; only explicit Cocoa missing-file errors now mark audio absent. Invalid/unknown paths are never opened, and `safeAudioURL` itself is unchanged.

## Evidence

- [storage-red.log](storage-red.log): original implementation, 3 test functions / 1 suite failed with 10 issues. The atomic transition test contains two cases. The temporary-permission test initially retried within the same open store; its final form also closes/reopens the store to prove durable retry behavior.
- [storage-green.log](storage-green.log): final focused regression **63 tests / 6 suites passed**. Five new test functions cover the atomic state change (two cases), read-only intact audio, stale-header permission recovery after reopen, interrupted SQLite chunk reconciliation after reopen, and per-record directory access isolation.
- [storage-directory-red.log](storage-directory-red.log): the adjacent directory-access issue was independently reproduced before its fix, **1 test / 1 issue**, with `.invalidPath` from a real `chmod 000` record directory. The final regression verifies the newer blocked record is visited first, the healthy older record recovers, the blocked original bytes/draft are retained, and permission restoration + close/reopen repairs it exactly once.
- SQLite reconciliation regression uses a real SQLite `RAISE(ABORT)` trigger, verifies unchanged original WAV bytes, unchanged audio epoch and preserved edited text, removes the trigger, closes/reopens the store, verifies 320 recovered frames and a second recovery count of zero.
- Existing cases in the same run cover actual SQLite `max_page_count` exhaustion/transaction rollback, injected audio write/sync failures, missing-audio text retention, interrupted tails, oversized WAV bounds, path/symlink ownership, deletion leases, pending deletion recovery, and archive/version retention.

Command:

```sh
SAYTILE_TEST_SCRATCH=/tmp/saytile-nokey-storage \
SAYTILE_TEST_LOG=/tmp/saytile-nokey-storage-directory-green.log \
scripts/test-native.sh --filter 'StorageRecoveryFailureTests|AudioStorageFailureTests|AudioJournalBoundaryTests|StoreRCTests|AudioTests|StoreTests'
```

`StoreSQLite` transaction semantics already roll back on body/commit errors and required no modification. Existing deletion intent + epoch + lease handling was retained; late recognition cannot make erased audio available again. No schema/migration change.

## Limits

This is a real native filesystem/SQLite test with independent synthetic fixtures, not a microphone/cloud or power-loss hardware test. File permissions and SQLite failure triggers were exercised; the user volume was not filled. Cloud correctness, real speech accuracy and physical device lifecycle remain separate evidence. A still-failing filesystem/database is reported as an error; the fix preserves original ownership for a later startup retry rather than claiming recovery succeeded.
