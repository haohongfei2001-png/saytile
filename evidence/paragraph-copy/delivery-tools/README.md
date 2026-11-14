# 0.17 paragraph-copy delivery scripts

**PREPARED_NOT_EXECUTED.** This directory only adapts the five existing `/private/tmp/saytile-015-delivery/` scripts. Preparation read source files, durable package receipts and hashes; it did not read the installed Apps or any private archive, stop/launch Apps, mount an image, compile, sign, install, run ASR or contact cloud services.

## Exact scope and baseline

- Source worktree: `/private/tmp/saytile-paragraph-copy`, branch `codex/paragraph-copy`.
- Required ancestor: `ab8545507c79640ec3f419e33467a0263c154844`, installed 0.15 (484). This branch does not include the 486 ASR changes.
- The parent supplied final committed source `570fd0a17b4c5eb7228f59fab1ecce2e43d07543`, 0.17 (485); branch, clean HEAD, version and build count were checked read-only. CI/native results remain the parent's separate evidence. Packaging refuses dirty source, wrong branch/HEAD/version, changed ASR runtime sources, storage-profile identity or entitlements.
- Retained prior package: `/Users/hhf/Documents/GitHub/saytile/dist/natural-paragraphs-0.15-484/Saytile-0.15-mandarin-arm64.dmg`, 64,920,442 bytes, SHA-256 `8dda6ce70631eb802ae117027c8e955a482de8cd092bfa4270bfa8b4a77061f7` (read and verified during preparation).
- Frozen helper SHA-256: `9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e`. Every Helpers / Frameworks / default.metallib byte and symlink target is checked against the extracted 484 runtime before/after signing and after DMG extraction. No ASR helper is rebuilt or re-signed; no model is installed.
- The prepared host version is 0.17; its build number is the final commit count and must exceed 484. The name and Bundle ID remain `Saytile 中文识别候选.app` / `app.saytile.mac.mandarin-candidate`.

## Parent execution after source freeze

Run these commands separately with the same final full SHA; no command below has been executed by this preparation.

```sh
python3 /private/tmp/saytile-017-delivery/package.py 570fd0a17b4c5eb7228f59fab1ecce2e43d07543
python3 /private/tmp/saytile-017-delivery/rollback.py 570fd0a17b4c5eb7228f59fab1ecce2e43d07543 > /private/tmp/saytile-paragraph-copy-release-570fd0a1/rollback.log 2>&1
python3 /private/tmp/saytile-017-delivery/activate.py --preflight 570fd0a17b4c5eb7228f59fab1ecce2e43d07543
```

`570fd0a1` is the first eight characters of the final SHA. Outputs are `/private/tmp/saytile-paragraph-copy-release-570fd0a1/`: `Saytile-0.17-mandarin-arm64.dmg`, staged `installed/Saytile 中文识别候选.app`, extracted `baseline484/`, `runtime484.json`, build/signature/Gatekeeper receipt, and source-bound `rollback.json`. A pre-existing stage causes failure instead of overwriting prior evidence. `stage-image.sh` and `validate-image.py` are unchanged from 0.15 and called by `package.py`.

After the parent independently completes its native candidate checks and decides to install:

```sh
python3 /private/tmp/saytile-017-delivery/activate.py --activate 570fd0a17b4c5eb7228f59fab1ecce2e43d07543
```

Only this explicit mode may stop the already-installed candidate and replace `/Users/hhf/Applications/Saytile 中文识别候选.app`. A bare SHA is not an activation command. Retain the 484 DMG and extracted baseline for rollback. The new DMG/App are separate from that old artifact. This script does not publish or notarize; signing later uses the existing Developer ID and Apple's timestamp service. Gatekeeper results are recorded as returned, with no override.

## Existing upgrade / rollback workflow retained

The only non-parameter adaptation is necessary because **484 already contains natural-paragraph schema 2**. The old 0.15 delivery script tested an earlier pre-sidecar 478 migration. This one instead requires the complete existing paragraph metadata to remain equal through **484 → 0.17 → 484 → 0.17**, without weakening assertions.

It reuses the final source's `scripts/mandarin/check-app-rollback.py` primitives and the same hash-pinned fixture probe. All launches use explicit fresh temporary data directories and deny network. The fixture contains two deterministic one-second WAVs, selected user edits, four revisions, drafts, stars, timeline relationships and original-audio hashes. SQLite schema 6/integrity/foreign-key assertions remain; hidden paragraph boundaries, a custom 180-second time interval, fresh zero-record archive and exact storage/Keychain **service-name contracts** are checked. No actual Keychain value is read. These are prepared checks, not claimed PASS results.

## Installation safety boundary

The existing atomic exchange and rollback-on-failure flow is retained. Preflight verifies old 484 and new final-SHA signed identities, old/new DMG digests, exact binary pair in the passing rollback receipt, runtime hash and the pinned candidate-only graceful-stop helper. It additionally compares the production App to the retained 484 activation receipt's **0.12 (373)** identity. The production App may be read for identity verification during later preflight/activation, but never replaced, launched or stopped by these scripts. If its identity differs, activation stops.

The process helper only targets the candidate Bundle ID **and** exact installed candidate path; it does not force-kill. Scripts never open, copy, delete or migrate user SQLite, original audio, preferences, model caches or Keychain secrets. The later normal candidate launch uses its existing candidate profile; it is not an isolated synthetic-data run. Installed candidate data and the separate production profile remain in place. A failed post-swap verification restores the old binary; uncertain recovery retains the staging copy instead of deleting it. The old signed DMG remains untouched.

## Preparation results

- Python AST / compile syntax: PASS (without importing or executing delivery scripts).
- Shell `bash -n`: PASS (no image staging).
- Durable 484 DMG digest and size: PASS.
- Pinned graceful-stop helper and fixture probe digest: PASS (read only; neither run).
- Build, signing, native acceptance, upgrade/rollback, activation: **NOT_RUN**; parent owns those operations after final source freeze.

`preparation.json` records both original and adapted script hashes; `adaptation.diff` shows the minimal changes. No product source, other worktree or installed bundle was modified by this preparation.
