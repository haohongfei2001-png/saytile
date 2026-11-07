# Independent connection-verifier review

Component regression: **12 Swift Testing tests / 1 suite PASS**, including 5 invalid-input/authorization cases, 2 WebSocket/HTTP cases and 2 high-frequency/retry-budget cases. See `connection-check-final.log`. This runs the actual verifier, Store, single-transcript coordinator, GPT request framing and validation with private in-process transport fixtures. It uses no network, Keychain, microphone or user archive and does not establish live provider access. Full URLSession loopback validation belongs to the separate protocol suite.

## Defects found and corrected by the implementation owner

- An already-cancelled attempt could read credentials before its first cancellation check. Entry and post-credential checks now prevent this; the regression proves zero credential/network calls.
- Missing credentials left untouched service cards marked “connecting”. The verifier now starts at “waiting”; only the failed service receives the authorization error and no network client starts.
- Empty or duplicate-service reports could pass vacuous `allSatisfy` checks. Cloud authorization now requires exactly three distinct service identities/providers and a nonempty completed transcript; a simulated report always remains `NO_API_ENGINEERING_READY`.
- Frequent ASR partials could consume all six GPT requests before EOS and permanently block final confirmation. `connection-check-budget-red.log` proves this with 8 partial revisions and a fast GPT peer. Check-only live review is now limited to one, preserving the six-request budget for bounded retries/fallback plus the final complete evidence. Normal recognition has no added live-review cap. The budget is atomic and shared across WebSocket sends and HTTP fallback; each actual request body includes 4096 output tokens.
- A superseded/stale partial review kept the fusion service failed even after the final authoritative review succeeded. `connection-check-review-status.log` shows the final transcript/pipeline succeeded but the fusion card failed. The verifier now uses the last run outcome; tests also require that the failed historical run, later completed run and arbitration usage evidence remain retained.

The initial fixture compile error and persistent-GPT manifest assumption error are preserved separately in `connection-check-initial-build.log` and `connection-check-fixture-error.log`. They are test-development failures, not evidence of product defects. `connection-check-review-status.log` also contains a fixture assertion affected by the parallel addition of persistent HTTP fallback; its stale-review failure is independent. `connection-check-green.log` is the penultimate all-green run; `connection-check-final.log` adds explicit retained-history assertions.

## Boundaries verified

- No authorization, missing consent, empty/odd/overlong PCM and cancellation on entry all stop before credential reads or provider construction.
- Successful fixtures cannot produce a live readiness level or enable cloud. A cloud-off input configuration is not mutated by an explicitly authorized check.
- Synthetic credential, topic and per-model context sentinels never appear in serialized reports or GPT request payloads; model contexts passed to the ASR fixtures are empty. Arbitrary NSError descriptions are replaced by safe diagnostic categories.
- One failed ASR does not erase the other ASR's verified status.
- The 90-second production constant is checked. A shortened 40 ms injected deadline and explicit cancellation both terminate the owned cooperative providers within the bounded test. This is not a real 90-second network timeout claim.
- Report matching invalidates on model identity, model name, region, workspace, consent or enabled-set changes. Cloud on/off, automatic recovery and the local topic do not change account identity. Key save/delete receipt invalidation is an AppModel responsibility, reviewed separately by the implementation owner.
- No `QUALITY_VERIFIED` or `PRODUCTION_READY` status is produced by these transport tests.

Reproduce from the repository root:

```bash
SAYTILE_TEST_SCRATCH=/tmp/saytile-connection-check-tests \
SAYTILE_TEST_LOG=evidence/no-api-product/local-input/connection-check-final.log \
scripts/test-native.sh --filter CloudConnectionVerificationTests
```

This component result predates the final integrated source checkpoint. Preserve these intermediate/red logs and use a new filename for the frozen-source regression.

## CI ownership-assertion correction

The full suite at `12ce5eac` exposed a fixture assumption: the real 40 ms watchdog can cancel before the second provider starts. Requiring exactly two stopped providers incorrectly rejected that valid early cancellation. The fixture now requires that the deadline actually elapsed and produced a cancelled service, that at least one provider started, that every started provider exited with balanced per-provider identities and zero active count, and that these counts remain unchanged after another 50 ms. The production deadline and runtime were not changed.

The subsequent **12-test component regression passed** in `connection-check-drain-fix.log`. Its raw safe counters were `started=2 stopped=2 active=0 per_provider_balanced=true` for both deadline and explicit cancellation. This local run does not claim to reproduce the exact CI scheduling order; the revised invariant also correctly verifies CI's one-start/one-stop case. Frozen-source full-suite verification remains required.

The `3f49682c` full CI run subsequently exposed a second fixture timing assumption: its 2-second wall-time assertion included Store initialization and runner scheduling, producing 2.1337 seconds despite every provider draining correctly. Timing is now anchored to first-provider-start → last-provider-stop for deadline handling, and explicit-cancel-request → last-provider-stop for cancellation handling. Initialization is logged separately; the actual 40 ms deadline, cancellation outcome, per-provider balance and post-return no-late-task checks remain unchanged. Production code and the 90-second connection-check limit are untouched.

`connection-check-timing-anchor-fix.log` contains the resulting **12-test PASS** and safe measurements: deadline setup 0.03249 s / active stop interval 0.03945 s; explicit cancellation setup 0.00563 s / cancellation-to-stop 0.000043 s; both `started=2 stopped=2 active=0 per_provider_balanced=true`. This is a test-only correction. The already-running 30-minute soak continues against the unchanged `3f49682c` production source/binary hashes.
