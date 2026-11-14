# Saytile in-app update final independent review

- Reviewed source: `012999c2018f591f3cf9a529e4c0ae81e7b81f21` in `/private/tmp/saytile-in-app-updates`; HEAD and clean working tree independently read on 2026-11-15.
- Comparison: installed paragraph-copy source `58bc8f96f79942881d1ae3221fd6219635833907`, plus correction diff since first reviewed updater source `c8d9ee20c6ed8981d5850642a84517e2e1c7f2ab`.
- Scope: read-only source/configuration/artifact-metadata review. No app launch, native test execution, compilation, signing, network update, private archive or credential access.
- Result: **no outstanding P0/P1 found in reviewed changes; prior three P2 findings corrected.** This is code/configuration approval, not a claim that runtime acceptance or CI passed.

## Corrected findings

1. `AppUpdateController.swift:52–56,80–89,114–125` now retains the actual offered version. Reopening an existing gentle-reminder session preserves an available-update explanation rather than inventing a new check; terminal callbacks clear retained offer state, restore the menu title and clear a stranded checking message. Sparkle's `canCheckForUpdates` remains authoritative; using session-in-progress as an unconditional disable would incorrectly prevent bringing the update back into focus.
2. `AppUpdateController.swift:91–104` treats Sparkle 4008 (authorization deferred) as normal deferral and 4007 as cancellation. Other errors retain failure reporting. Error-domain checks remain in place.
3. `AppUpdateController.swift:30` uses a neutral install-consent explanation, so disabling automatic checks no longer leaves a contradictory claim that automatic checking is active.

## Confirmed source safeguards

- One retained updater, MainActor state changes, weak action closures and KVO observation; menu/settings consume the same enabled/title/state model. No speech-panel buttons or status added.
- Normal update source is returned by delegate from signed bundle configuration, ahead of editable Sparkle defaults. Standard and Mandarin bundle/channel identities are distinct. Loopback requires the separate explicit fixture identity.
- Each offered item must have successful signed-feed validation. Numeric two/three-component versions are normalized to three components; a lower display version is rejected and UInt64 build must strictly increase. Equal normalized display versions with a higher build are intentionally permitted by the current tests. Malformed/prerelease labels and UInt64 overflow are rejected.
- `SURequireSignedFeed=true`, signature-failure expiration `0`, verification before extraction, automatic download/install disallowed, profile sending disabled. Gentle scheduled discoveries update existing menu/settings state without focusing a window or pausing capture.
- `SaytileApp.swift:462–478` preserves the existing cancel → asynchronous `prepareForExit()` → terminate sequence. Unpersisted drafts refuse termination. `AppModel.prepareForExit()` remains unchanged: invalidates target-input ownership, pauses capture, flushes editors, shuts down audio, awaits refresh, then closes the store. No new force-exit path in normal product operation.
- The final diff does not modify ASR/VAD/PCMJournal/SQLite timeline or external input delivery logic. AppModel product changes are updater presentation properties only. Update-review bootstrap resolves a strictly owned disposable identity before choosing its archive/preferences and before creating AppModel; ordinary app bundles contain no fixture marker.

## Actual candidate metadata read

Both `payload/Saytile 中文识别候选.app` and `installed/Saytile 中文识别候选.app` under `/private/tmp/saytile-in-app-update-release-012999c2` contain:

- version `0.18`, build `492`, exact source `012999c2018f591f3cf9a529e4c0ae81e7b81f21`, `SaytileSourceDirty=false`;
- bundle/update identity `app.saytile.mac.mandarin-candidate`, channel `mandarin`, matching source-configured HTTPS Mandarin feed;
- exact source public key; decoded Ed25519 key SHA-256 `32cbd20d060df765b39cc5b914629f633323cad751fdb7eeef692f029fcc7d73` matches the packaging receipt;
- all required signature/privacy/automatic-update flags listed above, daily interval 86400, no `SaytileUpdateReview` marker.

Source configuration SHA-256 independently read: `36a6efeb577be5b3168891ffb896afa5d47a7b0d8c649b3e072770f9c1b67be0`, matching `package.json` and `packaging-scope.json`.

## Evidence limits

- `build.log` records a completed build. Existing `package.json` records Developer ID signature checks PASS and DMG SHA-256 `654b08e926d90c88e0cb05ff4a5c116aa6c87c6cd59f7d71c24ca028c0d5f933` (64,972,638 bytes). This reviewer read those receipts and plists; did not rerun codesign or rehash the DMG while native acceptance was active.
- The same receipt correctly records Gatekeeper rejection as **Unnotarized Developer ID** and no notarization submission. It must not be presented as notarized public distribution acceptance.
- Root/fixture agent is running final real-host update and native settings acceptance. No results or counts from those in-progress runs are inferred here. Final PR CI and final-source runtime receipts must be appended by their owners.
- Public feeds are presently signed empty channels according to the integration task. This review establishes configuration only, not public update availability or a public-feed install/relaunch success.
