# Prepared 0.15 packaging and isolated upgrade / rollback

**PREPARED, NOT EXECUTED.** This preparation did not sign, build, launch, stop, install, or replace any App. It did not inspect the installed bundle or user SQLite, recordings, preferences, model caches, or Keychain values. Only source/build scripts and the durable 478 distribution artifact were read.

Worktree: `/private/tmp/saytile-natural-paragraphs`, branch `codex/natural-paragraphs`. Base: `7fd9296d8eb2bd81379bbaa7287844d0d46703d5`, 0.14 (478). The parent supplies the final committed 0.15 SHA. The packager refuses a dirty worktree, a different branch/HEAD, changed runtime source, storage identity, entitlements, or brand source.

## Parent execution after source freeze

```sh
python3 /private/tmp/saytile-015-delivery/package.py FINAL_SOURCE_SHA
python3 /private/tmp/saytile-015-delivery/rollback.py FINAL_SOURCE_SHA > /private/tmp/saytile-natural-paragraphs-release-SHORT_SHA/rollback.log 2>&1
python3 /private/tmp/saytile-015-delivery/activate.py --preflight FINAL_SOURCE_SHA
```

The preflight is read-only. Signing/disk-image operations and network-denied native smoke programs need an authorized execution environment. `activate.py --activate FINAL_SOURCE_SHA` is a separate, later parent-controlled operation and **has not been executed by this preparation**.

Output: `/private/tmp/saytile-natural-paragraphs-release-<first 8 SHA chars>/`.

- `Saytile-0.15-mandarin-arm64.dmg`, source-bound `package.json`, actual `build.log` and Gatekeeper result.
- `installed/Saytile 中文识别候选.app`: temporary staged artifact, not the user's installed path.
- `baseline478/`: a read-only copy extracted from the retained original DMG.
- `runtime478.json`: hashes and symlink destinations for every Helpers / Frameworks / default.metallib file. These must match after signing and after DMG extraction.
- `rollback.json`, `rollback.log`: exact old/new binary identity, generated-fixture legacy-table and original-WAV checksums, additive metadata checks.

The prior artifact remains `/Users/hhf/Documents/GitHub/saytile/dist/panel-boundary-0.14-478/Saytile-0.14-mandarin-arm64.dmg`, SHA-256 `7ecc7bb6bd09e4a764df091b86780fc6c4ee4d84a628017e7aeadb72af5b2212`. The old helper SHA-256 remains `9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e`. No ASR is recompiled; no new model is downloaded or run. The user-facing installed candidate identity/path stays `app.saytile.mac.mandarin-candidate` / `/Users/hhf/Applications/Saytile 中文识别候选.app`. Production `Saytile.app` is never replaced.

## Actual rollback checks prepared

The runner imports and verifies the migration primitives from the final committed source's existing `scripts/mandarin/check-app-rollback.py`; it does not duplicate database seed behavior. Every App/probe launch denies network and uses a new explicit synthetic directory. The old signed package and new signed package are copied into that temporary test root. No installed App or archive is used by this runner.

1. Seed two deterministic one-second WAV originals, four immutable text revisions including selected user edits, two drafts, stars, existing time groups, and the existing dispatch fixture. Preserve old table rows and both WAV hashes as the reference.
2. Open the same fixture with old 478, new 0.15, old 478, then new 0.15. Each must preserve the complete legacy snapshot and original file hashes, `user_version = 6`, `integrity_check = ok`, and no foreign-key violations.
3. The first new open must create exactly one `timeline_paragraphs` row per original, valid paragraph starts, the natural-paragraph trigger, and `natural_paragraph_schema = 2`. Old reopen and repeated new reopen must leave all this additive metadata identical.
4. An isolated explicit `break_hidden` value is written only into the test copy, then must survive both old/new reopen. This tests metadata retention, not the native edit gesture (that has separate UI evidence).
5. The prior default 120-second time group changes to 60 seconds as designed; a separate explicit 180-second setting must remain 180 after new migration and old reopen. Legacy historical group IDs do not change.
6. A fresh new archive must initialize with zero records and a 60-second interval. The original unmodified fixture remains byte-logically equal throughout.
7. Evaluate storage-profile and Keychain **service-name** contracts using each exact source and signed Bundle ID; do not read actual Keychain secrets.

These prepared assertions are not PASS results until the final binaries run them. They do not claim actual private user-data migration or microphone recognition.

## Activation safety

The prepared activation checks exact installed 478 + staged 0.15 + retained 478 DMG + passing source-bound rollback pair, bundle/team/entitlements, executable/worker hashes, image digests, and source ancestry. It uses the already-verified graceful-stop helper and atomic exchange. On first exchange failure it identifies the unchanged old bundle and restarts it only if it had been running. On post-exchange launch/identity failure it restores and verifies the old bundle. If recovery cannot be proven, it retains the staging bundle instead of deleting the only recovery copy. The retained original signed DMG is never deleted. No notarization, Gatekeeper override, or production publish occurs.
