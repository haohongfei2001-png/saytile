# Final 0.21 (557) evidence

Product source: `9aace8f5b0d7082bd67d2e9b1b6e1db6dcf05883`.
Fixture correction / full Xcode test source: `94db534265597e4bc26109e2d849b2406f62edb3`.
All later evidence-only commits must have no product/source/resource/runtime/build-script diff from the product SHA. `binary-and-corpus.json` binds actual machine, DMG, executable, bundled workers, linked SaytileKit, original MandarinCohort fixture and public manifests.

- `fixed15/{old,new}`: alternating wall-paced signed native runs. Root `auto-*.json.gz` includes model output, publications, actual displayed frames, final archive and wave hash. Per-clip `process.json.gz` has App+helper CPU and simultaneous footprint. Duplicate copies are omitted, no observations discarded.
- `pressure8`: old/new/new/old with 8 independently measured workers, target total 5.333 cores. All four `*-load.json.gz` prove actual load. The native receipts include every failed/late interval, not just improved passages.
- `comparison.json`, `quality440.json`, `product440.jsonl.gz`: unmodified CER scorer and explicit original/derived denominators. 440 whole recordings have text; 443 completed subsegments and five pre-existing failed subsegments are NOT all-success.
- `run-beta-021-*.py`: actual run order and paths. These call existing `measure-preview-cost.py`, `measure-loaded-preview.py`, and `score-live-cadence.py`; adjust only environment paths to reproduce on another checkout.
- `gate-replay`: baseline LocalLiveText copied from 533 (renamed only), replay driver and all before/after output. Compile against final SaytileKit and provide original `auto-*.json` receipts retained in the first/second integration directories. This controls identical model candidates, **not** live ASR timing. All final model text remains unchanged.
- Native folders: original machine JSON/logs and unmodified representative PNGs. Every generated scene's SHA is retained in `images-sha256.json`; full screenshots remain with the local delivery evidence. Scene-state injection is explicitly described in receipts.
- `foreground-failed-557*`: original failed job/artifact; `foreground-94db534.zip` and `ci-94db534-*`: corrected real isolated WKWebView/AppKit/TextEdit/Chrome and complete Xcode results. No silent rerun, skipped test or product input-safety relaxation.
- `signature.json`, `package-build.log.gz`, `update/receipt.json`, `rollback.json`: signed candidate, real Sparkle installer and data-preserving upgrade/rollback. Gatekeeper rejection is retained. No notarization success is claimed.

Compressed files are ordinary deterministic gzip (`mtime=0`). Git repository `SHA256SUMS.txt` binds all committed evidence. No private audio, credentials, personal archive, or chat content is included. The actual candidate app was invoked with explicit isolated directories, public audio and private clipboards; installed 533 remains intact. Release decision is [HOLD](../../../docs/delivery/beta-021/STATUS.md).

- `soak.json`: 905-second wall-paced signed native run; every archived chunk byte-matches the public source stream, all 47 rows completed, idle release/resume verified. RSS/CPU are sampled process measurements, not whole-machine power.
- `empty-final`: targeted unchanged-model diagnosis of all five pre-existing empty subsegments. Raw worker empty finals confirmed; no false silence or completed-state claim.
- `ci-94db534.json`: four workflows/six successful jobs, full Xcode 567 Swift Testing + 30 XCTest and 220 AppModel checks. Actual hardware sleep remains BLOCKED despite the job completing with an explicit unsupported-host receipt.
