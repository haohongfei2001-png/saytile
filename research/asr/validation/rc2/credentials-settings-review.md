# RC2 BYOK and native settings review

2026-11-07; started from PR4 `1caa46b6`. This is credential-free engineering verification, not cloud connection acceptance.

## Findings and fixes

1. **Presence checks fetched plaintext:** `CloudCredentialStore.contains` delegated to secret `read`, so merely opening settings retrieved stored secret bytes. It now uses an attributes-only Security query. Runtime provider `read` remains explicit and separate. Saved/missing/unavailable are distinct; inaccessible Keychain no longer masquerades as a missing key during Apply. No user credentials were read during this review.
2. **Failed save/remove looked successful:** the UI always cleared the entered key after save and hid Remove after deletion, even on errors. AppModel returns success/failure; failed saves retain input, deletion refreshes real metadata, and failures remain visible. All Security operations disable authentication interaction rather than unexpectedly prompting from background work.
3. **Draft settings confused applied state:** AppModel now captures the Apply candidate before asynchronous work, serializes Apply requests, exposes the last applied configuration and pending-change state, and updates applied state after the audio controller accepts the candidate. Later draft edits cannot silently substitute a different candidate midway through Apply.
4. **Provider/region changes retained inappropriate settings/authorization:** provider selection atomically resets consent, region, Workspace and price estimates while retaining configuration identity; it selects the already-supported provider model default. Region and purpose changes reset consent. Provider changes are handled in the Binding setter so moving between primary/optional rows cannot skip an `onChange` callback. No new adapter/model family was introduced.
5. **Technical setup dominated the normal settings:** primary Qwen/Assembly/Astra/Gemini/Scribe rows have local preparation status; Soniox/Meta remain available in a secondary disclosure. Role/provider/model/reasoning/price fields moved under Advanced. Highest-quality/fast mode uses a segmented control. Readiness explicitly describes local configuration, not proven remote connectivity; no credentials or consent are auto-enabled. Added custom models start disabled.

## Actual verification

- `CloudCredentialTests` and `RecognitionSetupTests`: **5/5 PASS** using Swift Testing, macOS Security.framework, and synthetic values only.
- Real Keychain operations used fresh `com.saytile.tests.credentials.<UUID>` services and fresh account IDs, not production `com.saytile.byok.v1`. Tested create, replace, read, provider/account/service separation, deletion, idempotent deletion, and rejected empty replacement preserving the existing synthetic value. Test entries cleaned up with defer. No existing credential scan, no prompts, no credential values printed by the tests.
- Independent UserDefaults suite verified configuration round-trip, stable IDs, no credential fields; defaults retain five primary services enabled but all consent/cloud flags off, optional Soniox/Meta off. Provider-reset validation tested.
- Full current Swift app sources compiled successfully after the native view edits (`settings-build.log`). Known CLT link search-path warnings did not fail the build.
- `git diff --check` passes.

Commands:

```sh
SAYTILE_TEST_SCRATCH=/tmp/saytile-rc2-credentials-tests SAYTILE_TEST_LOG=/tmp/saytile-rc2-credentials-tests.log scripts/test-native.sh --filter 'CloudCredentialTests|RecognitionSetupTests'
swift build --scratch-path /tmp/saytile-rc2-credentials-tests
```

Root runs the integrated actual native settings interaction checks separately; this report does not count screenshots or compilation as proof of interaction. Real provider authentication, real charged usage and quality remain untested without authorized credentials and processing consent. The settings do not claim a saved key is a verified connection.

## Stable native interaction identifiers

Section: `recognition.cloudEnabled`, `.configureServices`, `.inputMode`, `.topicContext`, `.automaticRecovery`, `.apply`, `.notice`, `.unapplied`, `.addModel`.

Model row: `recognition.model.<lowercase configuration UUID>.disclosure`, `.enabled`, `.region`, `.workspace`, `.secret`, `.saveKey`, `.removeKey`, `.consent`, `.purpose`, `.provider`, `.modelID`.
