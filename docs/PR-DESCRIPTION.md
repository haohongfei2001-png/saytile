## Summary

Recover and preserve the Always-On Voice / Saytile design baseline, then reconstruct the two unuploaded review deltas without claiming they are the missing originals.

- Separate audio-only erasure from record deletion; retain transcripts, all revisions and search/reuse.
- Persist per-binding/per-utterance stable UTF-16 dispatch ranges and snapshots; no automatic replay on uncertainty/restart.
- Align the seven-scene interactive prototype and documentation with Saytile V1.
- Preserve V2 quiet speech and V3 vocabulary/keyboard input as future work.
- Do not hard-code local-first as a product principle.

## Executed local verification

- Inherited synthetic PCM/SQLite: 10/10.
- Reconstructed SQLite/filesystem contracts: 37/37.
- Chromium DOM checks: 48/48. localStorage is a declared memory double; actual persistence is covered separately by SQLite reopen tests.
- Swift 6 interfaces: typecheck pass. Foundation UTF-16 smoke: 6/6.
- Original recovery files preserved byte-for-byte; delivery checksums provided.

## Not claimed

No native microphone/ASR, macOS external-app insertion, ALAC, battery/energy or native UI validation. Shared-file deletion is conservatively deferred by the reference model, not reported as erased. This is a design/recovery PR, not an installable application.

The user authorized publication to this existing public repository. No credentials, real recordings or private browser data are included.
