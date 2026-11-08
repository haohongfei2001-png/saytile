# Production AppModel connection lifecycle — isolated evidence

Scope: compiled the real `Sources/SaytileApp/AppModel.swift` with `tests/fixtures/AppModelProbe.swift`. A narrow internal `AppConnectionDependencies` value replaces only credential storage, verification, configuration application and immediate revocation. Its default `.live` calls the unchanged production Keychain, verifier and AudioController paths. Tests run with temporary databases and unique UserDefaults suites, no microphone, no window activation, no user data, no real Keychain operations and no provider network requests.

## Root-cause review and repairs

- **Fixed by root and verified here:** an apply that has already admitted cloud configuration but is still waiting for old sessions to drain cannot survive a later credential/consent invalidation. AppModel owns the apply task and its generation; synchronous AudioController revocation changes the factory before awaiting cleanup. The late apply cannot republish its former cloud snapshot or settings. Replacement checks await prior cancellation and configuration drains.
- **Reproduced and fixed here:** a residual settings action could start another connection check after `prepareForExit()` completed. Connection, apply and credential mutation entry points now reject actions both during and after exit. Concurrent exit callers await the same outstanding cleanup. Immediate revocation occurs before awaiting connection/apply cleanup.
- **Reproduced and fixed here:** cancelling a check left pending service rows indefinitely at “connecting/receiving.” Cancellation now settles unfinished rows as cancelled, while preserving verified and failed terminal outcomes. Generation checks still reject every late progress/completion event.
- **Reviewed:** root's verifier cancellation checks now precede credential access and session creation. This probe does not replace its separate transport-level cancellation tests.

## Observed coverage

The original 25 archive/editor/panel checks remain. Thirty additional checks exercise the actual AppModel methods: missing keys, missing authorization, blocked unverified cloud enable, failed credential save/delete, all three account/receiving states, failed service results, fake progress versus verified receipts, successful receipt admission, synchronous revocation during an unpublished apply, old-apply completion, cancellation state, stale callbacks, sequential replacement checks, credential removal during verification, exit while verification/apply is outstanding, late actions after exit and concurrent exit callers.

A report with `live=false` and completed simulated results is proven unable to enable cloud or persist a live receipt. A separately labelled **TEST_ONLY live-shaped injected report** exercises the positive admission branch. It is deliberately fabricated for controller branch coverage and is **not** a service connection, recognition accuracy result, billing observation or live acceptance certificate. No such test report enters production preferences or production archives.

## Red/green evidence

- `app-model-connection-red.log`: the existing checks and preceding connection cases pass, then the closed-model late-action assertion fails (probe exit 133).
- `app-model-cancel-state-red.log`: preceding cases pass, then the unfinished-service cancellation-state assertion fails (probe exit 133).
- `app-model-connection-green.log`: **55 checks pass**, including 30 new connection lifecycle checks. `app-model-connection-green-build.log` retains the complete build and run transcript.
- Each probe invocation used `SAYTILE_MODEL_SCRATCH=/tmp/saytile-no-api-model-connection` and the existing `scripts/test-app-model.sh`. No new test runner or separate simulated AppModel was introduced.

Remaining boundary: production provider authentication/recognition quality is still unverified without explicitly authorized real credentials and requests. Local controller evidence is separate from the real URLSession-to-localhost protocol simulator evidence.
