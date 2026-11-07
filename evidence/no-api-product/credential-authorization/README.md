# Credential account authorization closure

Scope: current PR #6 worktree after `3f49682c77c7c80beba3d2075c99ae32c0455c04`; these targeted results concern the uncommitted follow-up, not the prior frozen binary. The root delivery manifest identifies the final source commit.

## Confirmed defect and correction

Changing a stored credential retained its configuration ID, so a per-record scope based only on provider/model/region/workspace could authorize automatic replay to another account. `app-model-before.log` captures the failing production AppModel assertion: a successful credential save had no persistent account generation.

`ModelConfiguration.credentialGeneration` is now an optional opaque UUID, never a key or key hash. Legacy JSON without this field decodes to nil. Successful save or deletion rotates it; failed mutations leave it unchanged. Draft, applied, and persisted configuration receive the new generation, including disabled optional services. The connection receipt fingerprint and saved-audio scopes include this generation. Stale editor IDs/providers are rejected before credential operations.

The production controller invalidates its connection receipt and synchronously revokes cloud recognition **before** invoking a credential mutation. Failure remains local; it does not retain a misleading active receipt. In-flight credential reads are fenced again after returning by `RecognitionFailover` (implemented and separately tested by the owning agents).

## Targeted verification

- `app-model-after.log`: **66 AppModel checks PASS**, including successful/failed CRUD, UUID persistence, disabled-service persistence, stale editor rejection, pre-mutation runtime revocation, and stale apply/exit handling.
- `configuration-tests.log`: **5 tests / 2 suites PASS** for legacy decoding, config roundtrip, generation-bound receipt mismatch and existing setup contracts.
- AppModel used injected synthetic credentials and TEST_ONLY live-shaped receipts solely to exercise controller state; **no Keychain, real API, microphone, user audio, external input, or window activation** was used by this targeted run.
- These checks do not establish cloud account acceptance or real ASR quality.

## Independent integration read-review

Reviewed the new `AudioCapture.beginUtterance`, `AudioController.retry`, factory snapshots, `RecordingCloudAuthorizationScope`, Store authorization APIs/schema, and UI retry action. Capture fixes its configuration before journal/database suspension; automatic replay requires all current destinations to be covered by per-record authorization; schema migration does not infer authorization from older model runs. The explicit retry button uses the applied configuration, captured at the click; if the runtime configuration differs, the queued action is restricted to local recognition. New account generations prevent old recording scopes from matching after credential replacement. Deleted/unavailable audio cannot be granted or admitted by these APIs. No additional confirmed P0/P1 was found within this read-review scope after these corrections.

Validation limits: no production data/key namespace was accessed, no real cloud request was made, and the new combined frozen build still requires the root's final regression/packaging run.
