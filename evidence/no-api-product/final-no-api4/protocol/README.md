# no-api.4 exact-source native and localhost protocol run

Source **`a6849128e12e88560daa52fce48f6f2d805a88aa`**, tree **`5ab4abea901e1d880abadbe4b4b673ca939f076d`**, PR #6. This is the complete run for this frozen source, not a sum of prior or focused checks.

Executed once in a new scratch directory:

```sh
SAYTILE_SIM_FULL_SUITE=1 SAYTILE_SIM_EVIDENCE=evidence/no-api-product/final-no-api4/protocol SAYTILE_TEST_SCRATCH=/tmp/saytile-no-api4-final-native scripts/test-protocol-simulator.sh
```

**PASS: 386 test functions / 46 suites / 506 expanded scenarios, zero skipped or NOT_RUN lines.** Swift Testing elapsed **33.830 seconds excluding compilation**. Parameter cases replace their containing parameterized function in the expanded count; they are not counted twice. Protocol coverage runs in this same invocation: **12 functions / 52 scenarios**, **50 actual localhost network cases**, **zero peer contract violations**. Two invalid output-cap cases reject configuration before opening a network connection.

The **205** recorded Sources/tests/scripts/contracts/package/workflow/packaging hashes, HEAD and tree stayed unchanged before/after. Runtime paths were clean. The scratch directory did not exist before the run. `run-after.json` records the freshly built actual Mach-O executable and test-bundle hashes/sizes, distinct from root's separately packaged release App. No source file was edited by this run.

| Boundary | Actual observation |
| --- | --- |
| Input conversion | All four sample rates preserve complete waveform against the contiguous reference; 22,050 Hz returns 44,125/44,125 frames, repeated EOS drain empty, no padding |
| Production small PCM/tail | 50×640 + 198 bytes; both actual peers receive exactly 32,198 bytes with equal hashes |
| Two expert clients | The same complete PCM reaches actual production URLSession clients through provider-specific start/results/EOS |
| Failures | 14 ASR fault cases, 10 GPT WS faults and 7 HTTP faults preserve safe failures and reject unsupported/model-mismatched results |
| Persistent GPT | Five normal/stale/cache-loss/disconnect/connection-limit cases preserve current evidence and bounded recovery |
| Connection check | Normal/fallback/churn each produce 2 actual GPT requests; per-review reconnect produces 4; every request carries max_output_tokens=4096 within the six-attempt cap |
| Publication | Valid and unsupported-evidence sessions each expose three changing Store revisions; unsupported selections yield no dispatchable final |
| Authorization/data/input | All current native suites, including saved-audio account scope, delayed credential-read revocation, lifecycle, storage and input ownership, are included without disabling the network suite |

`native-network.log` contains build/test receipts, `driver.log` adds the final wire audit, `wire-audit.json` preserves peer observations, and both manifests bind counts to source/artifacts. Deliberate HTTP failure/cancellation can close a peer before EOF; corresponding transport-close exceptions remain in `server.log`, with zero protocol-contract violations.

**Scope: SIMULATED_PROTOCOL_NOT_LIVE_CLOUD.** Clients, sockets, parsers, coordinator, Store and connection backend are production code; ASR/GPT peers are stateful local fixtures. No actual cloud key, paid call, microphone, private recording or production database was used. These receipts do not establish real account access, ASR accuracy, fusion quality gains or cloud latency. Final package UI/installation/idle evidence is separately owned and is not included in these native counts.

## Exact CI relationship

[Design-contract run 42314923515](https://github.com/haohongfei2001-png/saytile/actions/runs/42314923515) completed successfully. [Native run 42314923680](https://github.com/haohongfei2001-png/saytile/actions/runs/42314923680) **FAILED** at the render-only native-window step. Its full native/protocol run (386 functions / 46 suites), AppModel (78 checks), release build and both isolated CLI boundaries passed first. The first panel-content trailing closure entered unconditional validation and called an unconfigured AX helper: `UI_REVIEW_FAILED Native UI control helper not configured`. Local controls-mode coverage had not exposed this render-only branch error. `ci-native.log`, `ci-design.log` and `ci-snapshot.json` retain the complete original failure and terminal states; no old workflow was rerun.

CI did **not** execute real AX controls. Isolated startup, bundle preservation and artifact upload steps were skipped after this failure. This exact candidate therefore does not have a passing overall native CI result, even though its local native/protocol run passed. The subsequent closure-interface repair and preview checks belong to `compact-panel/ci-closure-fix`, not to this frozen-source result.

CI checked out generated merge **`8f3b3122d3c205a8b33f1e330fdc15649e521e0b`**, parents PR #5/base branch `4fa637a47ce869b7c7aade0ea7c0c121162e10ee` and PR #6 head `a6849128e12e88560daa52fce48f6f2d805a88aa`. The base is **not main**. Git commit metadata confirms merge tree **`5ab4abea901e1d880abadbe4b4b673ca939f076d`**, identical to local HEAD's tree; commit identities differ. Connector logs/runs/jobs provide CI evidence; the Git commit API supplies the tree omitted by the connector representation.

Prior e56/5c05/ef2/d4/3f evidence remains separate and was not rerun or added to these totals. Earlier failures are preserved; this run concerns only a6849128 and does not retroactively certify earlier candidates.
