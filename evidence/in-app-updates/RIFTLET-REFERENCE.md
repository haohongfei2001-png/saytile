# Riftlet updater reference review for Saytile

Read-only review, 2026-11-15. No Riftlet app launch, tests, signing, source changes, key reads or remote writes were performed.

## Source authority

- Local checkout `/Users/hhf/Documents/GitHub/Riftlet` is unrelated old WIP: `codex/saytile-tray-placement`, `87c3103c05634b28f2f7f0bb644ec803cb2ac2fb`; one untracked `scripts/__pycache__/`. Do not copy files from checkout HEAD or reset it.
- Inspected `origin/main` objects at `b5a412f6d37378b7cfef56e2f1e9524cc9b1ac6e`, independently matched against live GitHub branches/main GET. Main includes PR #101 and #102.
- GitHub latest release GET reports published immutable stable `v1.0.2` (24). Tag source `5b73c755ec1eb6d1aa2ef5b9390da6200b6108b9`; signed product source `876c7e829abeef865e442f9e46eaae495d1a9e09`. These are intentionally different and must not be conflated.
- Final DMG `Riftlet-1.0.2.dmg`, 12,416,741 bytes, SHA-256 `374fbe7b5a49938bf7d67c38a52a018941b672c382abdace63efbb4f73393931` matches the actual native-upgrade receipt.
- All source locations below mean the pinned main object, not the stale local working-copy file.

## Small implementation to reuse

1. `Sources/RiftletApp/ApplicationUpdater.swift:15–71`: one retained `SPUStandardUpdaterController`, explicit start and reported startup errors; project `canCheckForUpdates`, persisted automatic checks, available version and errors into the existing settings UI. Sparkle remains owner of scheduling, download and install. KVO does not trigger checks or create a second updater.
2. `ApplicationUpdater.swift:48–71`: an explicit user check activates the updater; gentle scheduled update reminders keep the automatic check from stealing focus. Existing update session is reused. For Saytile, show availability in menu/settings only, never add status to the transcript panel.
3. `Sources/RiftletUI/RiftSettingsCenterPages.swift:199–203` and `RiftSettingsCenterRendering.swift:105–115`: current version, Check for Updates, a daily-check switch; errors and official-download fallback appear only when needed. `SettingsProductPresentation.swift:73–85` is the minimal immutable UI projection.
4. `Sources/RiftletUI/RiftControlCenterController.swift:271–277,398–400`: same projection powers menu and optional update reminder. Do not copy Riftlet's whole control center or its unrelated collection controls into Saytile.
5. `Sources/RiftletApp/ScreenshotEntryHost.swift:126–138`, `RiftletMain.swift:1619–1627`: defer explicitly requested update presentation until capture/edit transaction ends; do not discard current capture. For Saytile, checking can be nondestructive, but quitting for installation must preserve PCMJournal, final drafts, SQLite and active external-input ownership.
6. `RiftletMain.swift:270–333`: normal Quit path drains work before termination; no force exit. It uses `.terminateCancel`, asynchronously prepares data, then retries termination only after a gate marks approval. A native test showed this app's `.terminateLater` loop did not run necessary MainActor work. Reuse the lifecycle principle; do not replace Saytile's proven quit mechanism without a demonstrated need.

## Trust and channel safeguards

- `Package.swift` pins Sparkle exactly 2.10.1; `scripts/sparkle_bundle.py:13–37,75–99,118–128` pins revision/upstream framework digest, embeds framework and cleans build-only rpaths. Components are signed child-first without inheriting host entitlements: `scripts/release-tool.py:789–800`.
- `Resources/Info.plist:12–20`: fixed HTTPS feed and public Ed25519 key; `SURequireSignedFeed=true`, `SUSignedFeedFailureExpirationInterval=0`, `SUVerifyUpdateBeforeExtraction=true`; daily checks enabled, automatic installation disabled. Private key never belongs in source or package.
- `ApplicationUpdater.swift:101–108`: require `.succeeded` signed-feed verification before accepting an offer, then validate both display version and build advance. **Do not copy its strict three-part parser (`:76–90`) unchanged: Saytile currently uses two-part internal versions such as 0.17.** Implement a tested ordering rule matching Saytile's real version contract; no downgrade or same-version replacement disguised by a larger build.
- `scripts/check-update-identity.swift:29–91,116–139`: validate both complete signed apps and candidate against the installed app's actual designated requirement, not just displayed team or Bundle ID. Identity matching does not prove retained TCC permission.
- `scripts/release-appcast.py:122–215,229–260`: verify signed exact feed bytes, one fixed-host full artifact, immutable release digest/length, product identity, accepted source ancestry, notarized/stapled receipts, increasing version/build. Exact signed XML must not be reserialized after signing. Public feed change is a separate reviewed publishing action.
- **Do not reuse Riftlet feed, public key, Keychain account, Bundle ID or source-admission exceptions.** Saytile needs its own existing identity/key/channel. Testing uses separate ephemeral keys and localhost content; publication remains outside ordinary integration authority.
- **Riftlet runtime caveat:** `RiftletMain.swift:216–217` only checks ordinary capture mode, non-internal-acceptance and `.app`; it does not itself check the build-channel plist. Release tooling is responsible for its stable channel. Saytile should preserve/explicitly enforce its own candidate-vs-production policy rather than import that assumption.

## Reusable acceptance, and its limits

- `Tests/RiftletAppTests/ApplicationUpdaterTests.swift:24–39`: numeric version ordering, malformed/overflow versions, downgrade and equal-version rejection. Adapt to Saytile's actual numbering; don't weaken to lexical compare.
- `Tests/UpdaterAcceptance/make-fixtures.py:27–99`: independently signed A→B packages and signed feeds for no-update, available, wrong archive signature, corrupt archive, interrupted payload, old build, old marketing version and tampered signed feed.
- `Tests/UpdaterAcceptance/serve.rb:5–15`: localhost-only server, no-store feed, deliberately truncated body retaining original Content-Length for real interruption.
- **Fixture caveat:** that builder changes QA Bundle ID but does not prove an independent product data root. Run only on a disposable VM/account or add verified Saytile data isolation. Do not execute it against a user's ordinary installation.
- `scripts/test-release-appcast.py` plus `.github/workflows/native-foundation.yml:153–158`: actual Sparkle + CryptoKit signature tests and feed predecessor validation. `RIFTLET_SPARKLE_TEST_BIN` enables real QA-DMG signature rejection checks. Those do not prove installation/relaunch.
- `Tests/ReleaseUpgradeHost/run.py:142–154` deliberately requires a fresh GitHub-hosted macOS account; `:83–129` compares logical database/media/journal identities. This host test uses staged version replacement; it is complementary to, not proof of, Sparkle UI download/install.
- Strongest real evidence is `engineering/quality/2026-11-14/actual-formal-sparkle-update.json:1–116`: exact final notarized DMG, real Sparkle Install Update / Install and Relaunch clicked in isolated ARM64 macOS 27.2 GUI VM; old 1.0.1(23) → final 1.0.2(24); 12 assets/media, 5 operations, 3 START, 22 checkpoints, UNKNOWN state, settings, bookmark and draft hashes preserved; actual new system screenshot then collected and viewed. No unexpected replay.
- This receipt is **private signed loopback feed evidence**, not an assertion of actual public-feed upgrade, Intel/minimum-macOS/shared-Applications elevation or every TCC permission. It supersedes older 7-asset/zero-START private-candidate evidence for this question. Do not repeat stale claims that PR #101 remains a draft or no current stable Riftlet release exists.

## Recommended bounded Saytile integration

Retain one updater with existing Saytile version/feed identity, add the minimal settings/menu projection, preserve recording-safe quit and independent model/data directories. Verify: no-update; offered update/notes; cancel/defer; correct signed package install/relaunch; same versions rejected; corrupt/wrong-signature/interrupted downloads keep original installed app and data; automatic checks do not steal focus; synthetic SQLite/revisions/original-audio/model-cache/config hashes survive; actual new local recognition still works after update. Use an isolated profile/VM for real install, no personal recordings, no public release or feed mutation required to establish the private engineering loop.
