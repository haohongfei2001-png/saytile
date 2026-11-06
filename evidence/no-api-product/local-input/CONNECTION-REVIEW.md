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
