# Saved-audio cloud recovery scope

This is an isolated storage-layer verification, not a live cloud connection or
recognition-quality result. No credentials, microphones, private recordings or
production database were accessed.

## Confirmed defect

On baseline `3f49682c77c7c80beba3d2075c99ae32c0455c04`, a successful built-in
connection check enabled the global cloud configuration. The ten-second
background recovery loop admitted paused-state `queued`/`failed` recordings and
replayed them with that current configuration. There was no saved-audio upload
scope on the recording. Consequently, previously local historical audio could
be uploaded without a deliberate historical-audio action. The connection
sample itself was isolated; this defect was in subsequent automatic recovery.

## Storage change

- Schema 5 adds `recording_cloud_authorizations`, keyed by recording and canonical
  structured scope. All enabled destinations, including GPT text fusion, must
  be covered before automatic cloud recovery is permitted.
- Each scope contains configuration identity, provider, model, region,
  workspace, purpose and an opaque credential-generation UUID. It contains no
  API key, key hash, transcript or topic context. Credential generation is
  managed by the settings layer and changes when credentials change.
- `authorizeCloudRecovery(recordingID:configuration:)` validates every enabled
  service and consent before writing all scopes in one transaction.
- `permitsAutomaticCloudRecovery(recordingID:configuration:)` returns false
  for absent/insufficient authorization, unavailable audio or invalid cloud
  configuration. Database failures propagate; they are not treated as grants.
- Subsets and reordered destinations retain permission. Any new destination or
  credential generation requires explicit authorization for that recording.
- Older recordings receive no inferred/backfilled authorization, even if they
  have Apple fusion evidence or earlier cloud model-run metadata.
- Audio-only deletion preserves text and authorization metadata, but cannot
  authorize replay of unavailable audio. Whole-record deletion clears scope
  rows; the foreign key also cascades physical deletion.
- Schema 5 prevents an older schema-4 candidate from opening the database and
  applying the previous unrestricted recovery behavior. Released-app refusal
  and process migration checks are covered by the separate upgrade task.

The capture/retry caller must apply the result to the same configuration
snapshot used for recognition. Root owns that production integration and its
end-to-end synthetic regression; these Store tests alone do not prove routing.

## Evidence

- `store-schema-red.log`: before the Store change, one migration test failed
  two assertions: the database remained schema 4 and had no authorization
  table. This red result is specific to migration, not an actual upload.
- `store-scope-green.log`: **37 tests / 4 suites pass**, including eight new
  scope test methods. Parameterized methods exercise nine destination changes
  and six invalid/unauthorized configurations. Existing Store RC ownership and
  owned-range repair/migration tests also pass.
- The new cases cover restart persistence, isolation between recordings,
  scope expansion, credential rotation, explicit reauthorization, consent
  revocation, absent streaming services, schema-4 migration, transaction abort,
  closed database, malformed scope, deletion semantics and foreign-key cascade.
- `store-schema-build-plugin-missing.log`: initial invocation omitted the
  installed Swift Testing macro plugin. No tests ran. The established
  `scripts/test-native.sh` wrapper resolved this build setup failure.
- `store-scope-first-validation-fixture-failure.log`: two test cases initially
  changed a disabled optional model instead of the enabled GPT service, causing
  six assertions to fail. The fixture now explicitly selects the enabled text
  fusion service; production authorization logic was unchanged by that fix.

Command: `SAYTILE_TEST_SCRATCH=/tmp/saytile-cloud-recovery-scope
SAYTILE_TEST_LOG=evidence/no-api-product/cloud-recovery-scope/store-scope-green.log
bash scripts/test-native.sh --filter
'RecordingCloudAuthorizationTests|StoreRCTests|OwnedRangeRepairTests'`.

These are working-tree integration results after baseline `3f49682`, not the
final frozen delivery SHA. Final full-suite and package evidence must identify
the later integrated commit.
