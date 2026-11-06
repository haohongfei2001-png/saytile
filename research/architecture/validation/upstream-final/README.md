# PR6 upstream integration verification — 2026-11-07

Docs merge: `2018c0b02abc20b9575868e32cc2f81c03d833ac`; upstream PR4: `a602236ea48f7140b57c46e916bae4c5d43f5cd9`. Engine changes and this receipt are committed together. Source/test hashes identify the exact tested tree independently of the commit hash.

Command: `SAYTILE_TEST_SCRATCH=/tmp/saytile-upstream-final/build SAYTILE_TEST_LOG=/tmp/saytile-upstream-final/native.log scripts/test-native.sh --disable-sandbox`.

Full suite: **325 tests / 39 suites; 321 passed; 4 environment-blocked; exit 1**. No tests skipped or weakened; no model/reasoning substitutions. The four failures remain visible in native.log:

- `CloudCredentialTests.createReplaceReadDeleteKeepsAccountProviderAndServiceIsolation`: synthetic Keychain access `.keychain(100001)`.
- `CloudCredentialTests.invalidReplacementNeverErasesStoredDummyCredential`: synthetic Keychain access `.keychain(100001)`.
- `AudioPlayerIntegrationTests.silentPlayerSeeksAcrossChunksAndReleasesDeletionLease`: silent playback `无法播放原音`.
- `AudioPlayerIntegrationTests.silentPlayerNaturallyFinishesWithoutStartingMicrophone`: silent playback `无法播放原音`.

Ported PR4 regressions passed: independent review ownership remains until exit; EOS cancellation and watchdog both terminate durable attempts without changing confirmed text or original PCM. Storage recovery, tap format, lifecycle and replay pacing tests were preserved byte-for-byte from PR4. Existing single-GPT transport, mandatory final review, Apple candidate ingress, cloud outage failover and owned external range correction suites passed.

Product reconciliation: legacy acoustic review fixtures select actual ASR evidence using the sole GPT core; no Gemini/Scribe/second-reviewer defaults or old session actor restored. Store/AppModel merges retain PR4 recovery/refresh guarantees plus PR6 owned ranges and one consumer transcript. Engine package identity remains separate from PR4 RC2 candidate packaging.

AppModel probe: **25/25 passed; exit 0**. Command: `SAYTILE_MODEL_SCRATCH=/tmp/saytile-upstream-final/build SAYTILE_MODEL_LOG=/tmp/saytile-upstream-final/app-model.log SAYTILE_SWIFT_DISABLE_SANDBOX=1 scripts/test-app-model.sh`. Uses existing script, same isolated build cache, explicit probe module cache, synthetic SQLite and isolated UserDefaults, prohibited window activation; no microphone or real external target.

Boundaries: sandbox Keychain/playback acceptance remains blocked. Real cloud accuracy, paid APIs, physical devices/permissions, real external application editing, install/upgrade and release acceptance were NOT_RUN. No push, release, CI polling, production data or installed app changes.
