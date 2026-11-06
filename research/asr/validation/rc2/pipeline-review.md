# RC2 production pipeline review

2026-11-07. Parent PR4 source1caa46b6 plus current uncommitted RC2 changes. Scope: real capture/persistence/coordinator/dispatch paths, isolated synthetic audio and transport injection; no microphone, private store, actual API credential, network request, billable invocation or product install.

## Production path inspected

`CaptureWorker` journals each PCM block before offering it to `RecognitionSessionFactory`; a cloud ticket selects `MultiRecognitionSession`. Fanout gives independent bounded queues to enabled real-time providers. Only coordinator can publish candidate-backed fusion revisions. Live text reviews are triggered by actual conflicting evidence, finalization invokes enabled Gemini/Scribe acoustic reviews, then resolves remaining conflicts. Store owns version selection and durable reserved external prefixes. AppModel refresh consumes `directInputCandidates` and `latestDispatchableRevision`, then calls NativeInputCoordinator stable-range insertion. This is an actual production route, not a separate research-only wiring.

Raw-file recovery uses the same factory; model blocking/failure cannot prevent CaptureWorker journal completion. Async providers all receive immutable PCM; overflow fails only the affected stream, not the original journal. Closed-input jobs continue independently subject to bounded admission. Existing coordinator regressions cover review correction, failure, late callbacks, cancellation, same-PCM reuse and actual reserved-prefix protection.

## Fixed defects

1. **Settings/revocation during ticket creation (P1).** Both live capture and file retry read configuration to choose the Store ticket, await Store, then factory previously re-read mutable configuration. Switching local/cloud or removing a key while awaiting could create a different pipeline from the ticket or start a stale cloud session after the owner's cancellation scan. Factory now exposes a generation-stamped configuration snapshot, and both production callers use that exact snapshot. Admission and generation validation occur under the factory lock. Every update advances generation, including identical model settings after key removal. A stale admission creates only a preserved-recording failure, never a provider or Keychain request. Capacity and live behavior are otherwise unchanged. No fabricated original red log: the new snapshot API cannot compile against the old factory; causal pre-fix path was inspected, fixed behavior exercised.

2. **Startup automatic recovery could precede journal repair/import.** AudioController's normal 10-second recovery timer started independently of AppModel's `recoverAudio`, potentially claiming a record during long startup repair. AppModel now initializes the controller with startup recovery disabled and enables it only after `recoverAudio` succeeds. Background claiming additionally requires that gate; failed startup remains blocked with existing visible error. This is lifecycle ordering code review plus the normal AppModel regression, not a fake slow-disk timing measurement.

3. **Review activity was hidden by generic recognition labels.** AppModel queries the Store agent's bulk current-generation active phase API once for visible rows. `recognitionPhaseLabel` reports live text arbitration, audio review, or final ASR only while the logical record and corresponding current model run are actually running. Finishing/failing clears the phase. No percentages, invented progress or extra per-record SQL queries. Root owns final native presentation and real control inspection.

## New meaningful tests

`RecognitionFactorySafetyTests`: 2 tests (3 parameterized cases). Local→cloud and cloud→local change in the ticket gap, plus same-settings revocation, create no model runs and retain failed recording state.

`CaptureCloudIntegrationTests`: 1 test (2 parameterized cases). Real CaptureWorker begin/append/end, PCMJournal, factory, MultiRecognitionCoordinator, Store and dispatch reservation; only external transports/credential lookup are injected. Both experts receive identical journal PCM; Gemini and Scribe receive that exact PCM; Astra receives actual stored candidate evidence; preview reaches a record while capture is still open. Successful review creates the expected final revision, whose dispatch reservation is offered once. Injected Gemini failure retains exact original audio, candidates/text and a failed logical state. This proves internal product integration, **not real cloud connectivity or accuracy**. The test enters CaptureWorker at utterance begin (VAD/hardware are covered separately), and dispatch is the isolated durable ledger rather than an OS input target.

AppModelProbe: 21 inherited +2 real AppModel checks =23. Actual Store run phase appears through normal refresh as text review; after terminal failure the phase disappears and the fallback error state is shown. First fixture setup incorrectly configured only a non-streaming role, causing expected Store invalidSelection; corrected fixture adds its mandatory expert, without changing production validation. The failure log is retained and is not described as a product defect.

Commands/results:

- `SAYTILE_TEST_SCRATCH=/tmp/saytile-rc2-pipeline SAYTILE_TEST_LOG=/tmp/saytile-rc2-pipeline-regression.log scripts/test-native.sh --filter 'CaptureCloudIntegrationTests|RecognitionFactorySafetyTests|RecognitionCoordinatorTests|AudioShutdownTests|AudioLifecycleGateTests'` → **17 tests /5 suites PASS**. Counts overlap prior coordinator/lifecycle coverage; do not add this number to a full-suite count.
- `SAYTILE_MODEL_SCRATCH=/tmp/saytile-rc2-pipeline-model SAYTILE_MODEL_LOG=/tmp/saytile-rc2-pipeline-model.log scripts/test-app-model.sh` → **23 checks PASS**; nonactivating isolated process, no microphone/external input.
- `git diff --check` PASS. Root will run unified source checks/build/CI and record final commit identity.

## Still not proved

Actual Qwen/Assembly/Astra/Gemini/Scribe connectivity, real arrival timing and provider correctness need explicitly authorized credentials/audio/budget. Soniox/Meta implementations retained. No test here makes model ranking, measured quality improvement or RC2 readiness claims. Root's real native control, installation and source identity checks are separate evidence. Optional enabled services have no silent cost-based removal.

## Independent ownership review follow-up

The credentials/settings reviewer found two additional P1 cancellation ownership gaps. They were reproduced **before** the implementation fix by the new `CaptureOwnershipTests`:2 tests failed with3 assertions (`capture-ownership-before.log`).

- During `AudioController.stopCapture`, the old worker was removed from `worker` before `await old.stop()` and only added to draining ownership afterward. A concurrent settings/key revocation observed neither owner and returned without cancelling its already-admitted cloud job. The barrier fixture holds the real worker's run completion during the real controller pause; pre-fix cancellation count was0. The worker is now registered as draining synchronously before the first await, so revocation can cancel it while stop is suspended. The stopTask now includes pruning and all stop bookkeeping, preventing a start waiter from resuming during an incomplete stop-cleanup await.
- `CaptureWorker.cancelRecognitionAndWait` captured sessions then awaited, but removed every retired entry upon return. A new session retired during that await was incorrectly dropped from ownership and missed by the next cancellation. Cleanup now removes only identities in the captured session set (`ObjectIdentifier` on the class-bound protocol). The barrier test admits a new retired job while the first cancellation waits, then verifies it stays owned and is cancelled by the next request.

The only test seam is an internal AudioController initializer accepting an already-built CaptureWorker. Tests use synthetic RecognitionSession objects and asynchronous bounded barriers; no audio device, live provider or secret is used. **19 tests/6 suites PASS** after the fix, including both formerly red tests and prior capture/coordinator/lifecycle checks (`capture-ownership-after.log`). This targeted19 count supersedes the earlier17 scope and is not added to a full-suite total.

Read-only review of the credentials/settings changes found no additional P0/P1 in metadata-only presence checks, Keychain-only secret storage, provider/role/region consent reset, or immutable configuration apply snapshots. Save/remove only report success after Security.framework succeeds; UI secret input clears only on successful save; labels say prepared rather than connected. A possible transient status/notice ordering when removing a key during an applying-settings cancellation await is a UI concurrency limitation, not evidence of secret leakage or unauthorized provider admission. Actual cloud connectivity remains untested.
