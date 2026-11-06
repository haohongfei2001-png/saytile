# Independent capture and retry integration review

Reviewed the working-tree changes after baseline `3f49682` in
`AudioCapture.swift`, `RecognitionAudioFanout.swift`, `RecognitionFailover.swift`,
`SavedAudioAuthorizationTests.swift`, the archive retry button and recognition
settings. Source and fixtures are frozen for the next integrated runtime commit.

## Findings and corrections

1. **P1, corrected:** the archive button initially used draft settings while
   retry used the applied audio factory. Turning the draft cloud toggle off
   without applying it could label an actual cloud action “本机重新识别”. The
   button/help now use the applied configuration. AppModel captures that
   configuration synchronously at the click; `AudioController.retry` uses
   `expectedConfiguration` and restricts any changed configuration to local
   recognition. A task scheduling delay therefore cannot grant a new cloud
   destination under the old button label.
2. **P2, corrected:** global cloud availability previously allowed claims for
   historical audio now restricted to local recognition, even if Apple assets
   were unavailable. The automatic retry now checks the actual local route's
   availability before acquiring audio/starting recognition, then releases the
   claim when unavailable. The root task separately verified repeated attempts
   do not exhaust the saved record's retry allowance.

## Review conclusions

- Capture freezes its configuration before the first suspension in
  `beginUtterance`; the same snapshot grants the recording scope and creates the
  recognition session. A later settings change is rejected by factory generation
  checks, rather than widening this recording's destinations.
- Automatic retries never grant scopes. They check all persisted destinations,
  including fusion and credential generation, then use the requested snapshot
  or its same-generation `localOnly` restriction. No current-generation cloud
  configuration is substituted after the decision.
- Explicit archive retries grant only the selected recording, only under the
  configuration shown for that action. Existing audio leases, cancellation
  checks and independent PCM persistence remain in the path.
- Retry cancellation closes and drains its session before releasing its audio
  lease. A settings change between Store awaits and session creation is fenced
  by the unchanged generation check.
- Keychain mutations revoke the cloud epoch before touching the credential;
  the credential wrapper rechecks the epoch after a synchronous read returns.
  The settings agent separately reviews/tests credential generation persistence.
- No additional confirmed P0/P1 issue remains in this reviewed scope. This is a
  bounded review, not a claim of live provider verification.

## Added cancellation evidence

`CredentialReadRevocationTests.swift` exercises the actual
`FailoverRecognitionSession` / `MultiRecognitionSession` / transcript engine,
using fake providers and a bounded synchronous credential-read barrier. The
test invalidates the epoch while a synthetic read is in progress, then releases
the read. Cases cover the Chinese ASR credential and GPT fusion credential.

`credential-read-revocation-green.log`: **one test method, two cases pass**.
The revoked target starts no subsequent provider/fusion request, the session
finishes, and durable synthetic PCM remains byte-identical. No Keychain,
provider endpoint, microphone or private data is accessed. The existing
downstream cancellation guards also participate: this is an end-to-end
cancellation contract test, not mutant/red evidence that isolates the new
post-read guard as the only effective protection.

Command: `SAYTILE_TEST_SCRATCH=/tmp/saytile-credential-read-revocation
SAYTILE_TEST_LOG=evidence/no-api-product/cloud-recovery-scope/credential-read-revocation-green.log
bash scripts/test-native.sh --filter CredentialReadRevocationTests`.

The root task owns saved-audio controller matrix results and the final frozen
SHA regression/package evidence. No live cloud success is asserted here.
