# Frozen-source complete native and real loopback run

Source before and after: **`3f49682c77c7c80beba3d2075c99ae32c0455c04`**, PR #6. All 192 recorded source/test/script/package/workflow hashes remained unchanged during this run (`run-before.json`, `run-after.json`). Only evidence files were written.

Command, run exactly once:

```sh
SAYTILE_SIM_FULL_SUITE=1 SAYTILE_SIM_EVIDENCE=evidence/no-api-product/final/protocol SAYTILE_TEST_SCRATCH=/tmp/saytile-no-api-final-native scripts/test-protocol-simulator.sh
```

**PASS: 365 native test functions in 42 suites, 461 expanded scenarios, zero skipped/NOT_RUN lines.** Swift Testing elapsed 33.438 seconds excluding build. The opt-in production URLSession network suite ran inside that same invocation: **12 functions / 52 scenarios**, 50 actual network cases, zero peer contract violations. Two invalid output-budget scenarios correctly opened no network connection.

| Boundary | Observed result |
| --- | --- |
| Production 20 ms PCM and short EOS tail | 50×640-byte frames + 198-byte tail, exactly 32,198 matching bytes and SHA-256 at both peers; Qwen exact frames/tail, existing Assembly packetization within its frame limits; no padding |
| Two-provider full audio / EOS | Both actual URLSession clients receive identical PCM and complete the provider-specific lifecycle |
| ASR faults | 14 service/fault combinations remain failed instead of publishing completed transcripts |
| GPT protocol failures | 10 WS and 7 HTTP fault scenarios preserve the expected safe error classifications, reject malformed/model-mismatched data and avoid changing models |
| Persistent GPT | Five normal/stale/cache-loss/disconnect/connection-limit scenarios preserve actual evidence manifests and bounded recovery |
| Automatic check | Normal, HTTP fallback and changing-evidence cases each receive 2 GPT requests; per-review disconnect receives 4. Every actual request carries output cap 4096, all remain within the shared six-attempt budget |
| Publication safety | Normal and unbacked-selection production sessions both expose 3 changing Store revisions; valid final completes and invalid candidate selection leaves no dispatchable final |
| Cancellation, storage, lifecycle, input ownership | Included in the full native run, with no disabled network suite or filtered replacement |

The earlier CI `12ce5eac` red result is retained at `../../protocol/ci-12ce5eac-native-red.log`. The new explicit first-hypothesis barriers preserve the original-content and negation-correction assertions. Network cases run serially inside their suite; deliberate short timeout faults are unchanged. Unexpected HTTP errors now print only NSError domain/code when an assertion fails. The successful final run has no such failures.

Artifacts: `native-network.log` is the complete build/test receipt; `driver.log` additionally records the final wire audit; `wire-audit.json` contains actual peer observations; `run-after.json` records counts and artifact hashes. The summary computes expanded scenarios from passed function/parameter-case receipts and distinguishes them from Swift's function count.

**Evidence scope: `SIMULATED_PROTOCOL_NOT_LIVE_CLOUD`.** Clients, sockets, parser, coordinator, Store and connection-check backend are production code; ASR/GPT peers are stateful local fixtures. No real key, cloud endpoint, paid request, microphone, user recording or production database was used. This does not prove live account access, ASR accuracy, real-model fusion benefit or cloud latency. The separate CI snapshot identifies remote outcomes for this exact commit.

## Remote CI is a separate result

Final [design-contract CI run 42297305423](https://github.com/haohongfei2001-png/saytile/actions/runs/42297305423) completed successfully, including offline metric/provenance checks and `verify.py --ui`. `ci-snapshot.json` records both terminal outcomes: design success, native failure below. No workflow was rerun.

[Native CI run 42297305402](https://github.com/haohongfei2001-png/saytile/actions/runs/42297305402), triggered for PR head `3f49682c`, **failed with one issue**: `deadlineAndExplicitCancellationEndOwnedProviders` measured 2.133710958 seconds against its `<2 seconds` whole-test assertion. Its provider ownership/drain assertions passed, and all real network protocol tests passed (60.920 seconds for that suite). AppModel/build/UI/package CI steps were consequently skipped. This is not CI_PASS and has not been hidden by the local passing run. Actions checked out the generated merge `a6652a4c589168a36a9c77f734fa0db756841206` (head `3f49682c` into base `4fa637a47ce869b7c7aade0ea7c0c121162e10ee`); the local run above tested the head directly. The exact CI test log is retained as `ci-3f49682c-native-red.log`; the timing test owner was notified, with no production change or rerun performed in this verification task. See `ci-snapshot.json` for the terminal state of both workflows.
