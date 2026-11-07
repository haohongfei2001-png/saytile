# no-api.5 r2 native and localhost run

The single full local run for `4df87ad4dd7ff94da2027f0c978ca5c5cb1d7292` passed **391 test functions in 47 suites**, comprising **511 expanded scenarios**. Swift Testing took **34.165 seconds** excluding compilation. All suites ran, including the production URLSession protocol integration.

| Evidence | Local observation |
| --- | --- |
| Runtime tree | `ce2a3fed6a27a96ed4dca80abeac307793d4e705` |
| Source identity | All 208 tracked engineering inputs, HEAD and tree matched before and after execution |
| Build identity | New scratch `/tmp/saytile-no-api5-r2-final-native`, fresh executable and test-bundle Mach-O hashes in `run-after.json` |
| Playback regression | The production player published positive position 0.103 seconds, 0.123859042 seconds after `play` returned. The test confirmed ongoing playback, both chunk seeks, deletion lease release and retained text |
| Protocol suite | 12 functions, 52 scenarios, 50 actual localhost network cases, zero peer contract violations |
| Audio integrity | Four sample-rate conversions matched the complete reference. Production-sized 50 × 640-byte PCM frames plus a 198-byte tail reached both ASR peers with the same 32,198 bytes |
| Connection verification | Normal, unsupported-WebSocket and churn cases each made two GPT requests. Per-review reconnect made four within the six-request limit |
| Publication | Normal and unsupported-evidence runs each produced three changing stored revisions. Supported evidence completed final publication and the unsupported selection was rejected |

The test command was `SAYTILE_SIM_FULL_SUITE=1 SAYTILE_SIM_EVIDENCE=evidence/no-api-product/final-no-api5-r2/protocol SAYTILE_TEST_SCRATCH=/tmp/saytile-no-api5-r2-final-native scripts/test-protocol-simulator.sh`. `native-network.log`, `driver.log`, `server.log` and `wire-audit.json` retain the raw run. The before/after manifests record exact hashes and counters. Expanded scenarios count each parameter case once in place of its containing function.

The three localhost peers exercise Qwen and AssemblyAI WebSocket handshakes, complete PCM delivery, incremental results, EOS and failure handling, plus GPT persistent WebSocket review, bounded reconnect and same-model HTTP fallback. The production clients and coordinator use actual sockets. The peers emit controlled synthetic responses. This evidence has scope `SIMULATED_PROTOCOL_NOT_LIVE_CLOUD`. Real-provider access, speech accuracy, fusion gains and cloud latency remain pending.

The only tracked engineering-input change from 702a is the progress observation in `AudioPlaybackTests.swift`. The prior local failure, controlled timing experiment, focused correction and both previous CI logs remain in the 702a evidence. Results from those runs are excluded from this run's totals.

## CI results

[Native run 42325233633](https://github.com/haohongfei2001-png/saytile/actions/runs/42325233633) and [design run 42325233659](https://github.com/haohongfei2001-png/saytile/actions/runs/42325233659) both succeeded on the first automatic attempt. They checked out merge `9063ab185a180736fd36c9724375249d97eee231`, with parents `4fa637a47ce869b7c7aade0ea7c0c121162e10ee` (PR #5 base branch) and this PR #6 head. The Git commit API confirmed tree `ce2a3fed6a27a96ed4dca80abeac307793d4e705`, identical to the locally tested tree. `ci-merge-identity.json`, `ci-snapshot.json`, `ci-native.log` and `ci-design.log` retain the identity, terminal jobs, counters and raw logs.

The CI machine independently passed **391 functions / 47 suites / 511 expanded scenarios** in **58.252 seconds**. The player published position **0.131875 seconds** after **0.153896833 seconds** from `play` return. CI also passed the 50 localhost cases with zero violations, 97 AppModel checks, release build, 17 CLI guard cases, 7 setup cases, isolated startup and artifact upload.

CI rendered **22 native captures**. The near-bottom text check passed. All key/main capabilities and actual window states were false in 20 before-validation, 20 after-validation, 20 after-interaction and 22 capture checks. Outside foreground transitions counted zero. CI interactive AX controls have status `NOT_RUN`, consistent with the render-only command and zero AXPress/field-edit actions. The separately packaged local UI checks retain their own counts and receipts.
