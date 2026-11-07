# Automatic cloud-to-Apple failover — 2026-11-07

Base: `59a63f2f77520ae684dd97c65417b90140fab342`.
Branch: `engine/offline-failover-20261107`.
Scope: this offline worktree only; local commit, no push or merge.

## Implemented runtime path

`AudioCapture.swift / CaptureWorker.beginUtterance` and `AudioController.retry`
→ `RecognitionSessionFactory.make`
→ `FailoverRecognitionSession`
→ unchanged `MultiRecognitionSession / SingleTranscriptEngine` with observed injectable streaming providers.

A provider construction/run connection failure (including a non-cancellation URL transport error) signals the owner immediately. Authorization, quota and provider configuration failures also permit local continuation, but permanently block automatic cloud probes for the current runtime configuration generation. Cancellation and incomplete/protocol evidence are not classified as a network outage. A single failed ASR triggers handover; it never certifies dual-expert completion. Existing cloud candidates/previews remain in Store history.

The owner cancels and drains the old cloud session before starting a new `beginRecognition` ticket and Apple session. The old child is detached and its reference is released after the handover scope. Apple consumes only `JournalRangeReader.readPCMRange` data, from offset zero and then the increasing durable watermark. Live `append` calls continue to the journal independently and are not also forwarded into Apple. Thus replay and incoming live audio cannot overlap or leave a gap. There is no simultaneous local/cloud publisher for one ticket.

Replay reads at most 1,600 PCM16 frames (3,200 bytes) per 50 ms. It can catch up at approximately 2x real time without storing a whole recording. Existing bounded Apple queues still fail safely if the recognizer cannot keep up. Normal journal checkpoints publish each 16,000 frames (one second of captured audio); an uncheckpointed short tail waits for the next checkpoint or segment close. Input-close is read before the last watermark, and close is already published by CaptureWorker after final journal synchronization. Handover additionally waits for cloud cancellation acknowledgement and installed-resource availability. This is live durable-tail following, not a segment-close-only replay, and is not a guaranteed end-to-end latency claim.

`LocalCandidateIngress` publishes through existing Candidate/fusion Store tables. An unresolved or conflicting final cannot claim completion. Existing candidates, user drafts, original PCM and external UTF-16 reservations are retained. No dispatch operation is replayed by this implementation.

If Apple reports unsupported or uninstalled resources, the recording stays queued; capture continues. No asset prepare/download is called. The next segment also chooses local automatically while the cloud circuit is open. Existing persisted recovery claims, finite attempts and retry blocks are reused.

## Recovery and fencing

The circuit is runtime state, separate from saved configuration/consent. It coalesces concurrent initial failures, then admits at most one next-segment cloud probe after 5, 15 and 60 seconds. It stops after three failed probes in a configuration generation. A successful probe restores ordinary dual-ASR/GPT operation; it never upgrades/replays the current local ticket. There is no standalone reachability request or paid connectivity check. Recovery is discovered through a subsequent eligible segment or existing queued-recording retry, using current credentials and unchanged authorized model configuration.

`factory.update` invalidates the old epoch and synchronously cancels every registered owner before exposing a new snapshot, including identical-config credential changes. Checks surround asynchronous handover boundaries and provider callbacks. Two additive Store-actor helpers in `LocalCandidateIngress.swift` check the epoch inside the actor turn before queuing or minting a local ticket. They call existing Store methods; no schema, Store.swift, StoreSQLite, InputCoordinator, InputAccessibility or AppModel change was needed.

## Validation and exact coverage

All providers, credentials, availability responses and audio are synthetic/injected. No real microphone, Apple recognizer, installed app, production database/preferences/audio, Keychain access or cloud/API request was exercised by the new tests. The native test build compiles and links the full SaytileKit and Saytile executable modules; it does not launch the app.

| Test/path | Verified behavior |
|---|---|
| OfflineFailoverTests.liveFailureFollowsDurableTailThenRestoresDualCloudOnNextSegment | Actual CaptureWorker + factory + cloud coordinator; one ASR connection fails while capture remains open; original bytes equal journal bytes; Apple invoked automatically; checkpointed tail arrives before close; final tail included exactly once; no overlapping cloud/local provider lifetime; single local text; candidate history retained; stale callback rejected; next segment resumes both cloud ASRs and GPT with unchanged consent/configuration |
| unavailableAppleQueuesAndNextRecordingIsLocalWithoutAToggle (2 cases) | Unsupported locale/runtime and supported-but-missing assets both queue safely; capture continues; next recording uses newly available local provider during cooldown without cloudEnabled changes |
| revocationDuringAvailabilityFencesHandoverAndDropsOldOwners | Revocation during suspended availability prevents local handover and further unauthorized cloud provider dispatch; stale callback rejected; owned work drains |
| recoveryPreservesExternalReservationWithoutRepeatingStableText (2 cases) | Confirmed and unverified external reservations both survive a new recognition generation; no duplicate stable-range reservation; candidate history grows |
| nonNetworkFailureStopsAutomaticCloudAttempts (2 cases) | Authorization and quota failures remain blocked after advancing the injected clock; next recording can finish locally without another cloud request |
| circuitCoalescesFailuresBoundsProbesAndSeparatesAuthorization | Shared outage coalescing, single-probe admission, finite three-probe budget, authorization/quota/configuration blocking, cancellation classification |
| localFinalConflictingWithExternalPrefixCannotClaimCompletion | Conflicting local candidate is retained but cannot complete or alter the external prefix/unverified ledger |
| Existing factory/ownership tests | Pending ticket settings race, identical-config invalidation, worker ownership during stop suspension, newly retired sessions remain cancellable |
| Existing journal/storage/lifecycle tests | Bounded range crossing beyond 12 MB, no lifetime audio buffer, nondurable read rejection, storage failure watermark, capture tail, lock/sleep gating |
| Existing coordinator/fusion/Store dispatch tests | Failed/missing expert not counted as agreement; mandatory GPT review; stale/deleted generations rejected; user drafts retained; UTF-16 and unknown-delivery protections; audio-only deletion preserves text; finite recovery scheduling |

Final result: **79 native tests in 13 suites passed**, including 7 new failover tests (10 parameterized executions). Full SaytileKit and Saytile executable compilation/linking passed. Exact command and hashes are in `RECEIPT.json`; final output is in `scoped-tests.log`. Initial SwiftPM nested sandbox execution was denied; `--disable-sandbox` disables only SwiftPM's inner sandbox, with the outer workspace restrictions unchanged. An initial new-test compile error and a fixture binding-order error were corrected in the new tests only. Existing tests were not edited. Toolchain cache-write/link-search warnings remain nonfatal.

## Remaining limits / next work

- Real network outage, Apple SpeechAnalyzer resource availability/cancellation, device energy and Chinese/English recognition quality are **NOT_RUN**. The current live Apple adapter uses its existing zh-CN supported-locale/installed-resource check. No claim of equal quality to the dual-cloud/GPT path, English locale auto-selection, or measured accuracy improvement is made.
- The new circuit observes streaming ASR construction/run failures and credential-access errors. A GPT-only review failure while both ASR streams remain connected retains the existing evidence/failed-recovery behavior; it is not a new signal to replace the transcript with Apple. Existing GPT-failure regression remains unchanged.
- Provider cancellation must acknowledge before this recording switches publishers. Capture remains independent meanwhile and later segments can route locally; no attempt is made to run competing publishers if a provider fails to release.
- After three unsuccessful cloud probes, this runtime generation stays local/queued until configuration is reapplied/changed or the process restarts. Auth/quota/configuration faults require corrective configuration/credential action. Nothing silently changes saved consent.
- Runtime circuit state is intentionally not persisted. The existing durable per-recording recovery budget and retry blocks still apply after restart.
- Remote PR/CI status was not queried because this task forbids API calls and fixes the local base/branch. No remote mutation or release validation is claimed.
- Next acceptance, outside this task's authorization: isolated real-device Apple behavior and an explicitly authorized real network-outage/cloud-quality run. No installed RC1 changes are needed for the completed synthetic validation.
