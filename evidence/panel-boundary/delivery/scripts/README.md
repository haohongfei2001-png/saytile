# Prepared 0.14 packaging and isolated upgrade protection

Status: **PREPARED, NOT EXECUTED**. No application was built, launched, installed, stopped, or replaced by this preparation. No installed app, user archive, recording, model cache, preferences or Keychain secret was read. Only the durable 476 distribution artifact and project/build scripts were inspected. `preparation.json` binds the verified old DMG and prepared script hashes.

Worktree: `/private/tmp/saytile-window-boundary`, branch `codex/panel-window-boundary`.
Expected version: `0.14`. Supply the final complete source SHA; the packager refuses dirty sources or a different HEAD/branch.

## Ready commands (run sequentially after final SHA is provided)

```sh
python3 /private/tmp/saytile-014-delivery/package.py FINAL_SOURCE_SHA
python3 /private/tmp/saytile-014-delivery/rollback.py FINAL_SOURCE_SHA
python3 /private/tmp/saytile-014-delivery/activate.py --preflight FINAL_SOURCE_SHA
```

Use an authorized execution environment for signing, disk-image staging and the network-denied native smoke processes. The last command is read-only: it compares installed **bundle identity/code**, the staged candidate and the synthetic rollback receipt. It does not open databases, inspect secret values, or install anything. It has not been run in this task.

Output is `/private/tmp/saytile-window-boundary-release-<first 8 SHA chars>/`:

- `Saytile-0.14-mandarin-arm64.dmg`, `package.json`, `build.log`.
- `installed/Saytile 中文识别候选.app`: staged artifact only, not `/Users/hhf/Applications`.
- `baseline476/`: read-only image extraction copied into temporary build staging.
- `runtime476.json`: every runtime file hash and symlink destination, checked after signing and DMG extraction.
- `rollback.json`, `rollback.log`: old 476 → new 0.14 → old 476 on independent generated SQLite/WAV fixtures.
- `packaging-scope.json`: exact source and no-install scope.

The prior artifact is `/Users/hhf/Documents/GitHub/saytile/dist/local-mandarin-0.13-476/Saytile-0.13-mandarin-arm64.dmg`, SHA-256 `d66aeb66b038b553e7d7e7ec89d18572d5ef2b182e3619bbcce55f45e11b18b1`.

## Runtime preservation

The ordinary packaging script recompiles/re-signs nested runtimes. This temporary packager instead copies the immutable signed 476 runtime, compiles only the current Swift App, refreshes source-owned host resources, and signs only the outer App and image. The complete Helpers/Frameworks/default.metallib content must remain byte-for-byte identical. It refuses changes to runtime source, storage identity, entitlements or approved icon input that would make that reuse inappropriate.

Expected worker SHA-256: `9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e`. No ASR comparison or inference is launched by these scripts. The candidate Bundle ID and eventual installed path remain `app.saytile.mac.mandarin-candidate` and `/Users/hhf/Applications/Saytile 中文识别候选.app`; production `Saytile.app` is not replaced.

## Upgrade/rollback coverage and limits

The existing source-bound migration runner uses two deterministic synthetic recordings, manual preferred versions, editing drafts, stars, timeline links, PCM hashes and database integrity. It tests fresh startup, sequential old/new/old reopens and unchanged original fixture. Every smoke/seed process denies network access and uses an explicit temporary data directory. Keychain **service-name contracts** are evaluated from each exact source and bundle identity; no Keychain values are read. This does not claim inspection or migration of actual private user archives/settings.

The signing receipt records actual Gatekeeper assessment. An unnotarized Developer ID result remains explicit; this flow does not submit notarization or alter Gatekeeper/system settings.

## Installation stop boundary

`activate.py` is prepared from the existing atomic-exchange installer, updated to require old 476 / 0.13 and new 0.14, identical worker bytes and the tested upgrade pair. A bare SHA is rejected. It requires the explicit `--activate` operation for a later authorized installation; **do not run that operation during the current preparation**. It preserves the old durable DMG and retains staged recovery data if an atomic exchange cannot be conclusively recovered.
