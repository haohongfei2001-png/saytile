# Frozen-source native and real localhost protocol verification

PR #6 source: **`d4b9dbe812b9084f1bf31c1817c7b67095e17fc7`**, tree `01f8644b57935f7f9beb9759ad3e8f44dda2ce30`. The before/after manifests record **201** source, test, script, package, workflow and packaging file hashes. They and HEAD remained unchanged during the run; runtime paths were clean before execution. Evidence files are outside that frozen source scope.

Executed exactly once:

```sh
SAYTILE_SIM_FULL_SUITE=1 SAYTILE_SIM_EVIDENCE=evidence/no-api-product/final/protocol SAYTILE_TEST_SCRATCH=/tmp/saytile-no-api-final-native scripts/test-protocol-simulator.sh
```

**PASS: 378 native test functions in 45 suites, 495 expanded scenarios, zero skipped/NOT_RUN lines.** Swift Testing elapsed **33.388 seconds excluding build**. Expanded scenarios count parameter cases in place of their containing function, not in addition to it. The production URLSession network suite ran in this same invocation: **12 functions / 52 scenarios**, **50 actual network cases**, **zero peer contract violations**. Two invalid token-budget cases correctly opened no connection.

| Boundary | Actual observation |
| --- | --- |
| Production 20 ms PCM plus short EOS tail | 50×640 + 198 bytes; exactly 32,198 matching bytes and hashes at both peers; no padding |
| Two complete-audio experts | Production clients send matching full PCM and complete Qwen/Assembly lifecycle events |
| Failures | 14 ASR provider/fault combinations, 10 GPT WS faults and 7 HTTP faults preserve safe failure categories and avoid false completion |
| Persistent GPT transport | Five normal/stale/cache-loss/disconnect/connection-limit scenarios preserve the current candidate evidence and bounded recovery |
| Automatic connection backend | Normal, fallback and evidence-churn cases each make 2 GPT requests; per-review reconnect makes 4; each request carries max_output_tokens 4096 and shares the six-attempt cap |
| Production publication | Valid and unsupported-evidence cases each expose three changing Store revisions; valid final completes, unsupported selection produces no dispatchable final |
| Authorization and recovery | Full suite includes newly fixed old-audio/account scope, click-time applied configuration, credential generation, delayed credential-read revocation and storage migration behavior |

`native-network.log` contains the complete test receipts; `driver.log` adds the wire audit; `wire-audit.json` preserves real peer observations. The manifests record identity, counts and artifact hashes. `server.log` includes expected transport-close exceptions when deliberate HTTP error/cancellation cases close before peer EOF; those are retained, and peer contract violation count is zero.

**Evidence scope: `SIMULATED_PROTOCOL_NOT_LIVE_CLOUD`.** The clients, sockets, parsers, coordinator, Store and connection backend are production code. ASR/GPT peers are stateful local protocol fixtures. No actual cloud credential, paid API, microphone, private recording or production database was used. These results do not establish live account access, real ASR accuracy, fusion quality gains or cloud latency.

## CI identity and status

Both workflows completed successfully, with no rerun: [design-contract run 42300935247](https://github.com/haohongfei2001-png/saytile/actions/runs/42300935247) and [native run 42300935389](https://github.com/haohongfei2001-png/saytile/actions/runs/42300935389). Native CI (Swift 6.3.3, macOS 26 runner) passed the same **378 functions / 45 suites / 495 expanded scenarios** in **44.787 seconds**, all **50 network cases with zero violations**, **66 AppModel checks**, App build, cloud probe isolation (4 cases), setup CLI boundaries (7 cases), isolated startup, and candidate artifact upload.

The CI UI step produced 16 native captures and passed its rendering/state checks. It explicitly logged **`UI_CONTROLS_NOT_RUN remote AX helper not configured; rendering only`**. The zero-skip claim above applies to the complete native test invocation, not the entire CI UI surface. Native AX interactions require the separate local UI receipts; CI success is not evidence that those interactions ran remotely.

Actions checked out generated merge **`5dd66d8c3a8bd58bf8cad21289c9f875fdbd3883`**, parents main `4fa637a47ce869b7c7aade0ea7c0c121162e10ee` and head `d4b9dbe812b9084f1bf31c1817c7b67095e17fc7`. Its tree is **identical** to the local head tree above; the commit identities remain distinct. `ci-native.log` and `ci-design.log` record checkout and completed checks; `ci-snapshot.json` records both terminal outcomes and the explicit remote UI limitation. The GitHub connector supplied runs, jobs and logs; the Git commit API supplied the merge tree because the connector's commit representation omits the tree field.

Historical red CI evidence was preserved without rerunning its SHA: `../../intermediate-3f49682c/protocol/ci-3f49682c-native-red.log` and `../../protocol/ci-12ce5eac-native-red.log`. The current invocation is the newer frozen source and does not erase those failures.
