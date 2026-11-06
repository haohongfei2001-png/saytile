# Final AppModel and isolated input verification — no-api.3

Runtime **`ef2f8f84f377197350e6384f79af12a9b56272fd`**, tree **`126d4e2b2c24ea82f016708c03f9567cb297afab`**. All checks below ran once on this frozen source. The 198 tracked runtime, test and script files are unchanged before/after, digest `29caf78c71f1273b8957f71326f350a4f6efe3a889b82e87d48433edb207b2f8`. This does not inherit results from the superseded no-api.2 run.

| Layer | Actual result | Boundary |
| --- | --- | --- |
| Production AppModel integration | 66 checks PASS | Injected credential/connection/apply dependencies; no real Keychain reads or provider call. TEST_ONLY success receipts are not live evidence. |
| Headless DOM | 20 checks PASS | Production Swift coordinator + SQLite with test-only DOM target adapter; textarea/contenteditable preserve surrounding text, suppress repeats, invalidate changed context, never send. Not native AX. |
| Native NSTextView AX | 9 checks PASS | Real Accessibility reads/writes against owned invisible fixture, injected target selection. Includes UTF-16/suffix dispatch and safety failures. No production foreground resolver claim. |
| WKWebView context | 6/6 observer checks, 2 capability rejections, zero sends | Real background WebKit/AX. Setter acknowledgement did not mutate DOM: marked unverified once, never replayed. **Not a successful browser-insertion result.** |

Native and WK fixtures report foreground unchanged and no owned activation. They were cleaned up before handing the AX slot to the separately owned range-repair tests. No external visible browser, user profile, private draft, microphone or paid cloud call was used. Existing headless Chromium 156.0.8078.4 / Playwright 1.65.0 was reused.

`receipt.json` binds counts, source and all log hashes. The actual AppModel, DOM, AX and WK executable files were hashed immediately before execution and after completion; all six match. The official runtime/test scripts were unchanged. Evidence-only wrappers retain the AppModel executable and observe child-process hashes without changing fixture arguments or results.

Commands:

```sh
SAYTILE_MODEL_SCRATCH=/tmp/saytile-final-ef2f8f8-model SAYTILE_MODEL_LOG=evidence/no-api-product/final/input/app-model.log bash evidence/no-api-product/final/input/app-model-retained-runner.sh
SAYTILE_INPUT_SCRATCH=/tmp/saytile-final-ef2f8f8-input SAYTILE_INPUT_EVIDENCE_DIRECTORY=evidence/no-api-product/final/input python3 evidence/no-api-product/final/input/native-observed-runner.py
SAYTILE_INPUT_SCRATCH=/tmp/saytile-final-ef2f8f8-input SAYTILE_INPUT_EVIDENCE_DIRECTORY=evidence/no-api-product/final/input SAYTILE_PLAYWRIGHT_DIR=/tmp/saytile-rc-input/browser-tools SAYTILE_CHROMIUM_EXECUTABLE=/Users/hhf/Library/Caches/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-mac-arm64/chrome-headless-shell node --require ./evidence/no-api-product/final/input/dom-observer.cjs scripts/test-input-browser.mjs
```

There were no failures in this invocation. The older combined AX forbidden-operation failure remains UNKNOWN because its original per-operation counters were not retained; this new passing run does not reinterpret that historical signal. Production foreground target discovery remains NOT_RUN. Complete product readiness also requires the independently owned new 30-minute waveform/persistence comparison and package/actual UI results; these input results alone do not establish readiness.
