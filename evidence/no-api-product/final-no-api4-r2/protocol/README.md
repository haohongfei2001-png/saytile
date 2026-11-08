# no-api.4 r2 exact-source native and localhost protocol run

Source **`1067f1ad5c5c29c698f346651c965db2169625eb`**, tree **`1c59b5e95f92dd34b19d4fb390549724071114a6`**, PR #6. This is one complete run for this frozen source, not a sum of earlier or focused checks.

```sh
SAYTILE_SIM_FULL_SUITE=1 SAYTILE_SIM_EVIDENCE=evidence/no-api-product/final-no-api4-r2/protocol SAYTILE_TEST_SCRATCH=/tmp/saytile-no-api4-r2-final-native scripts/test-protocol-simulator.sh
```

**PASS: 386 test functions / 46 suites / 506 expanded scenarios, zero skipped or NOT_RUN lines.** Swift Testing elapsed **33.919 seconds excluding compilation**. Parameter cases replace their containing function in the expanded count. The same run contains **12 protocol functions / 52 scenarios**, **50 actual localhost network cases**, and **zero peer contract violations**. Two invalid output-cap cases reject configuration before opening a connection.

The **205** source/test/script/contracts/package/workflow/packaging hashes, HEAD and tree were unchanged before/after. Runtime paths were clean. The new scratch did not exist at start. `run-after.json` records actual newly built executable/test-bundle Mach-O identities; these are distinct from root's release package. No source was edited during this run.

| Boundary | Observation in this run |
| --- | --- |
| Input conversion | Four sample rates preserve the complete contiguous reference waveform; 22,050 Hz produces 44,125/44,125 frames with no padding and an empty second EOS drain |
| Production small PCM and short tail | 50 × 640 + 198 bytes; both production ASR clients deliver the same complete 32,198-byte PCM/hash |
| Failure boundaries | 14 ASR, 10 GPT WS and 7 HTTP fault scenarios preserve safe failures instead of publishing unsupported results |
| Persistent GPT | Normal/stale/cache-loss/disconnect/limit scenarios preserve evidence identity and bounded reconnection |
| Connection checks | Normal/unsupported/churn use 2 actual GPT requests; per-review reconnect uses 4; every check request carries max_output_tokens=4096 within the shared six-attempt cap |
| Publication | Valid and unbacked-selection sessions expose three changing Store revisions; unsupported evidence produces no dispatchable final |
| Authorization/data/input | Current native suites include per-record cloud authorization, credential-read revocation, lifecycle, storage recovery and owned input boundaries |

`native-network.log` is the full build/test receipt; `driver.log` also contains the final wire audit. `wire-audit.json` preserves real peer observations. Deliberate cancellation/failure may close a peer before EOF; the resulting transport exceptions remain in `server.log`, with zero contract violations. Manifests bind source and artifact hashes to the recorded counts.

**Scope: SIMULATED_PROTOCOL_NOT_LIVE_CLOUD.** URLSession clients, sockets, parsers, coordinator, Store and connection backend are production code; ASR/GPT peers are stateful localhost fixtures. No API keys, paid calls, microphone, personal audio or production database were used. These results establish neither live account access nor recognition accuracy, fusion gains or cloud latency. Release UI/install/idle evidence is owned separately and is not added to native test counts.

## Exact CI identity and terminal results

[Design run 42317977018](https://github.com/haohongfei2001-png/saytile/actions/runs/42317977018) and [native run 42317977017](https://github.com/haohongfei2001-png/saytile/actions/runs/42317977017) both completed **successfully**, without reruns. Full logs are retained as `ci-design.log` and `ci-native.log`; `ci-snapshot.json` records terminal jobs/steps, exact counts and log hashes.

The separate CI machine passed **386 functions / 46 suites / 506 expanded scenarios** in 59.807 seconds excluding compilation, with **50 localhost cases / 0 violations**, followed by **78 AppModel checks**, release build, **4 cloud-probe CLI cases**, **7 setup CLI cases**, isolated startup, bundle preservation and artifact upload. These CI counts are not added to the local total.

Its repaired render-only path completed **20 native captures** and actual native text/UTF-16 checks. Key/main capability and actual state were false in **18 before-validation, 18 after-validation, 18 after-interaction and 20 capture checks**. There were zero outside-foreground observations. **CI native AX controls: NOT_RUN** — its command intentionally has no `--controls` or AX helper; zero AXPress and zero field-edit checks are recorded. This demonstrates the repaired render-only path on the CI Swift 6.3.3 runner, not remote interactive-input acceptance.

CI checked out **`8eaffdc0f86541a7c9a0c91c9e1cf769c21545a5`**, whose parents are PR #5/base branch `4fa637a47ce869b7c7aade0ea7c0c121162e10ee` and current PR #6 head `1067f1ad5c5c29c698f346651c965db2169625eb`. The base is **not main**. Its tree is **`1c59b5e95f92dd34b19d4fb390549724071114a6`**, equal to local HEAD's tree despite a different commit identity. The Git commit API supplied the tree omitted by the connector; `ci-merge-identity.json` preserves it.

Earlier a684/e56/5c05/ef2/d4/3f runs remain separate and were not rerun or added to these totals. The a684 CI render-only failure is retained; it is not retroactively certified by this run.
