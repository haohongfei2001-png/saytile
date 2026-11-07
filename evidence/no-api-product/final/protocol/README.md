# no-api.3 frozen-source native and localhost protocol verification

Source **`ef2f8f84f377197350e6384f79af12a9b56272fd`**, tree **`126d4e2b2c24ea82f016708c03f9567cb297afab`**, PR #6. Both manifests record **204** source, test, script, contract, package, workflow and packaging hashes. HEAD, tree and every recorded hash remained unchanged; runtime paths were clean. Evidence files are outside this frozen source scope.

Executed exactly once for this source:

```sh
SAYTILE_SIM_FULL_SUITE=1 SAYTILE_SIM_EVIDENCE=evidence/no-api-product/final/protocol SAYTILE_TEST_SCRATCH=/tmp/saytile-no-api-final-native scripts/test-protocol-simulator.sh
```

**PASS: 379 native test functions / 46 suites / 499 expanded scenarios; zero skipped or NOT_RUN lines.** Swift Testing elapsed **33.698 seconds excluding build**. Expanded scenarios replace parameterized functions with their actual case count, rather than counting both. The production URLSession network suite ran in this same invocation: **12 functions / 52 scenarios**, **50 actual network cases**, **zero peer contract violations**. Two invalid token-budget cases correctly opened no connection.

| Boundary | Observed result |
| --- | --- |
| Converter input ownership | All four sample rates match the contiguous whole waveform; 22,050 Hz now returns 44,125/44,125 frames, repeated EOS drain empty, no padding |
| Production 20 ms PCM plus EOS short tail | 50×640 + 198 bytes; both peers receive exactly 32,198 matching bytes and hashes |
| Two complete-audio experts | Actual URLSession clients send matching complete PCM and finish Qwen/Assembly protocol lifecycles |
| Service failures | 14 ASR provider/fault combinations, 10 GPT WS faults and 7 HTTP faults preserve safe failure categories and reject false completion |
| Persistent GPT | Five normal/stale/cache-loss/disconnect/connection-limit cases keep current candidate evidence and bounded recovery |
| Connection backend | Normal, fallback and evidence churn each make 2 GPT requests; per-review reconnect makes 4. Actual requests carry max_output_tokens 4096 within the six-attempt cap |
| Publication safety | Valid and unsupported-evidence sessions each expose three changing Store revisions; invalid selection produces no dispatchable final |
| Saved-audio authorization | Current full suite includes old-audio/account scopes, click-time applied configuration, credential generation and delayed credential-read revocation |

`native-network.log` contains full build and test receipts, `driver.log` additionally records final peer audit, `wire-audit.json` records real local observations, and `run-after.json` records counts and hashes. Peer transport-close exceptions from deliberate HTTP error/cancellation cases remain visible in `server.log`; contract violation count is zero.

**Scope: `SIMULATED_PROTOCOL_NOT_LIVE_CLOUD`.** Clients, sockets, parsers, coordinator, Store and connection backend are production code; ASR/GPT peers are stateful local fixtures. No real cloud key, paid API, microphone, private audio or production database was used. This establishes neither live service account acceptance nor ASR accuracy, fusion gains or cloud latency. The four-rate waveform test does not replace the separately owned new 30-minute continuity run.

## CI identity and status

Both workflows succeeded with no rerun: [design-contract run 42307570836](https://github.com/haohongfei2001-png/saytile/actions/runs/42307570836) and [native run 42307570857](https://github.com/haohongfei2001-png/saytile/actions/runs/42307570857). Native CI (Swift 6.3.3/macOS 26 runner) passed **379 functions / 46 suites / 499 expanded scenarios** in **45.707 seconds**, all four converter rates waveform-equal, all **50 network cases / zero violations**, **66 AppModel checks**, App build, isolated CLI boundaries, startup and artifact upload.

CI produced 16 native window captures with rendering/state checks, but explicitly logged **`UI_CONTROLS_NOT_RUN remote AX helper not configured; rendering only`**. The native suite's zero-skip count does not claim remote AX interaction coverage; actual controls require the separate local UI receipts. Full logs are `ci-native.log` and `ci-design.log`; `ci-snapshot.json` records terminal states, identities and the UI limitation.

The actual CI checkout is generated merge **`760f8741193e2a6c60e42629560eb9fa7c5aa0fc`**, parents PR #5/base branch `4fa637a47ce869b7c7aade0ea7c0c121162e10ee` (not main; main is `a352a1c`) and head `ef2f8f84f377197350e6384f79af12a9b56272fd`. Its tree **`126d4e2b2c24ea82f016708c03f9567cb297afab`** equals the local head tree; commit identities remain distinct. Logs identify checkout; the Git commit API supplies tree metadata omitted by the connector's commit representation.

Older no-api.2 results remain under `../../intermediate-d4b9dbe/` and are superseded for delivery by the confirmed intermediate converter gap. They must not be presented as new-source or long-duration correctness evidence. Historical CI failures and converter red receipts remain preserved. No old SHA or workflow was rerun.
