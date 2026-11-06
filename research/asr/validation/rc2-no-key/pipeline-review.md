# RC2 no-key pipeline lifecycle review

Date: 2026-11-07 (Asia/Shanghai). Baseline: `45af67049ddee2553fe1929a812aecb83cc157e4`; fixes are in the shared RC2 worktree for root integration. No credentials, production recordings/database, microphone, or network requests were used.

## Fixed defects

1. **Cancellation stopped owning the live review during finalization.** The session's cancellation handler ended when the streaming task group finished. `finalize()` then awaited an independently scheduled live arbitration task outside that handler. The finish watchdog cancelled only the session task, leaving the awaited review active; explicit cancellation could return from `finalize()` without transitioning the durable recognition attempt out of `running`. The handler now covers streaming and finalization, followed by a cancellation check that enters the existing durable failure path. Original audio, candidates, and the already-confirmed text remain intact.
2. **A cancelled live review could outlive session completion.** `coordinator.cancel()` cancelled its review and immediately discarded the task reference. During active streaming, `session.wait()` could therefore return and release factory capacity while the review transport was still unwinding. Cancellation now retains and awaits that task. Concurrent cancel callers await the same task; only `reviewDidFinish()` clears ownership. The review's failure/cleanup paths do not call `cancel()`, so this wait does not create a self-await cycle. Actor suspension permits review cleanup to reenter the coordinator.

The existing dependency seam gained a default no-op finalization observer, and the internal session initializer accepts a test deadline; the production deadline remains 480 seconds. These let fixtures establish the exact finalization boundary rather than infer it from a sleep.

## Reproduction and regression evidence

- `finalization-before.log`: new finalization test, two cases (explicit cancellation and 150 ms watchdog), **3 failed assertions**: both left durable state running; watchdog also failed to complete the session. The fixture had already observed streaming model runs completed and a live review blocked at the finalization boundary.
- `review-drain-before.log`: new streaming-phase cancellation test, **1 failed assertion**: session completed while its controlled review had acknowledged cancellation but had not exited.
- `finalization-after.log`: first fix, 10 coordinator tests passed; superseded for final-state coverage by the broader run below.
- `pipeline-after.log`: **53 tests / 5 suites passed** after both fixes: coordinator, audio fanout/review boundaries, Chinese protocol, English protocol, Meta protocol. Coordinator coverage is 11 test methods, including two new methods / three new cases. Tests verify preserved raw PCM/candidates/confirmed text, no running model records after cancellation, and no cancelled review candidate publication.
- `pipeline-build-overlap.log`: one intermediate build stopped before tests because another agent was changing the AudioTap `sampleRate` interface. After that interface froze, the same targeted invocation passed. This is not counted as a test failure or a successful run.

Command:

```sh
SAYTILE_TEST_SCRATCH=/tmp/saytile-rc2-pipeline \
SAYTILE_TEST_LOG=research/asr/validation/rc2-no-key/pipeline-after.log \
scripts/test-native.sh --filter 'RecognitionCoordinatorTests|RecognitionPipelineBoundaryTests|ChineseProviderProtocolTests|EnglishProviderProtocolTests|MetaProviderProtocolTests'
```

## Other reviewed boundaries

- Fanout preserves independently bounded expert queues and explicitly fails only an overflowing expert; the review snapshot cannot silently become truncated audio.
- Qwen/Soniox/Assembly/Meta keep EOF ordered behind PCM, validate final/evidence state, and cancel their sockets on transport cancellation. Meta additionally paces PCM at real time and checks both endStream-write completion and normal server close. Existing protocol fixtures were rerun; actual service behavior remains unverified.
- Found saved-audio replay feeding 200 ms of PCM every 100 ms while Meta drains at real time. Delegated to the AudioCapture owner; its production pacing fix and evidence are in `lifecycle-review.md`, not this change.
- FinalASR and precision review use URLSession async requests with cancellation and explicit request timeout values (120/180/300 seconds, depending on service/mode). The session watchdog requests cancellation; it does **not** forcibly terminate arbitrary cancellation-ignoring code. The injected noncooperative review test releases its gate explicitly, proving ownership is retained until exit. Request timeouts are not represented as guaranteed hard wall-clock kill deadlines.
- Read-only review of root's `AppModel.refresh()` coalescing: fixed request versions, shared task identity, and a completed-version watermark cover waiting callers without recursively manufacturing more refreshes; operation identity prevents an old waiter from clearing a newer operation. Requests arriving during a pass require a later pass. Exit rejects new refresh work and awaits the accepted pass. No P0/P1 found in that change; its independent runtime evidence remains `app-model-before.log` / `app-model-after.log`.

## Limits

This verifies cancellation, durability, bounded queue behavior, and protocol fixtures with isolated synthetic data. It does not verify any live vendor connection, real recognition quality, billable request outcome, or real-microphone behavior, and supplies no model-ranking or accuracy claim. Final integrated regression and commit are owned by the root agent.

Integration note: the final test-only watchdog is 1 second, with a 3-second observation window, to leave headroom for full-suite/CI scheduling after the finalization handshake. Original 150 ms red evidence is unchanged; the production deadline stays 480 seconds and all cancellation/state/audio assertions are retained.
