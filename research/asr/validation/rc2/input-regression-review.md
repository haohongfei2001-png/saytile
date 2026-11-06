# Current-source native input and headless browser regression

2026-11-07. Runtime SaytileKit source `8f2d71b73c8ae1aa421719201a263de20d98fc7f` remained unchanged. This work repairs and runs the existing input probes; it adds no product runtime behavior, model evaluation or general test framework.

## Script repair

The existing `Store*.swift` / `Input*.swift` static compile lists no longer include the schema3 fusion/configuration dependencies. Actual pre-fix compilation failure is retained in `input-build-before.log`; no fixture was launched by that failed compile. `test-input-native.py` now builds/links the package's static SaytileKit with test visibility, using the established CLT/SwiftPM module-map layout. The DOM runner calls its `--compile-dom-only` mode instead of repeating a stale shell glob. Four probe sources conditionally import the package; standalone compilation compatibility remains. Production source is unchanged.

`SAYTILE_INPUT_EVIDENCE_DIRECTORY` directs all evidence to this RC2 directory. No historical `evidence/rc` record was overwritten. The existing Playwright installation requested absent browser1254; that failure is retained in `input-browser-missing-runtime.log`. The existing runner override selected cached headless Chromium1248 instead, with its actual version recorded. No visible external browser, profile, account, download or payment was used.

## Results and exact limits

- **Native AppKit AX: 9 checks PASS** on the single attributed followup. Production coordinator/SQLite/AX targeted only a separately launched owned invisible text fixture through an injected target selector. Unicode increment, duplicate suppression, selection changes, cancellation and no replay passed. The owned fixture and probe never activated; outside activation count0 on that followup.
- **Real WKWebView AX: 6/6 mutation invalidations PASS**, plus large-tree/blank-context automatic binding rejection and zero sends. Some cases rely on the final semantic recheck when an AX notification is absent. **Insertion remained `unverified` and the DOM value stayed `PREFIX|SUFFIX`.** This is a safely retained single uncertain attempt, not successful browser insertion. No activation or retry was used to force it through.
- **Headless DOM: 20 checks PASS** across textarea and contenteditable, with real production coordinator/SQLite and a test-only DOM access adapter. Incremental UTF-16 insertion, surrounding-text preservation, duplicate/no-send behavior, selected-range and same-URL/replacement/navigation/focus mutation protection passed. This is not native AX or real foreground application proof.

The first native run completed its insertion/selection assertions but failed an un-attributed start/end global foreground equality assertion. `input-native-first-unattributed.log` and `input-native-first-unattributed-actions.log` preserve it. The followup added identity-only activation observation for the owned fixture/probe, with either activating still a hard failure; unrelated transitions are separately recorded without inferring cause. Exactly one attributed followup was run. These results do not prove global foreground constancy across all runs or blame the initial observation on the user.

Artifacts: `input-native-run.log`, `input-native-coordinator.log`, `input-webkit-observer.log`, `input-browser-run.log`, `input-browser-dom.log`, `input-regression.json` (runtime SHA and actual binary hashes).

## Reproduction

```sh
SAYTILE_INPUT_SCRATCH=/tmp/saytile-rc2-input \
SAYTILE_INPUT_EVIDENCE_DIRECTORY="$PWD/research/asr/validation/rc2" \
python3 scripts/test-input-native.py

SAYTILE_INPUT_SCRATCH=/tmp/saytile-rc2-input \
SAYTILE_PLAYWRIGHT_DIR=/tmp/saytile-rc-input/browser-tools \
SAYTILE_CHROMIUM_EXECUTABLE=/Users/hhf/Library/Caches/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-mac-arm64/chrome-headless-shell \
SAYTILE_INPUT_EVIDENCE_DIRECTORY="$PWD/research/asr/validation/rc2" \
node scripts/test-input-browser.mjs
```

Existing Accessibility permission only; no prompts. Neither `--foreground-batch` nor its opt-in environment flag was used. No production data, real user applications/drafts, browser profiles, microphone or cloud service was accessed. Python/Node syntax and `git diff --check` pass.
