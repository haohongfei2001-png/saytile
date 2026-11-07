# no-api.5 initial frozen candidate

The local full Swift run for `702a24b9767826275f650c70f7e118365601a2a8` **failed**. One silent-playback test sampled zero progress after a fixed 180 ms wait. The original test output and wire receipts are retained. This commit received one full local run.

| Local result | Observed |
| --- | --- |
| Runtime tree | `f5a357a00b97a246ee5c6ee0a95272738c135c0d` |
| Source identity | 208 tracked source, test, script, packaging, contract and workflow inputs matched before and after the full run |
| Native tests | 390 passed, 1 failed, 391 functions in 47 suites |
| Expanded scenarios | 510 passed of 511 attempted, zero skipped |
| Test elapsed time | 34.356 seconds excluding compilation |
| Protocol suite | 12 functions and 52 scenarios passed |
| Actual localhost peer | 50 network cases, zero recorded contract violations |
| Failing function | `silentPlayerSeeksAcrossChunksAndReleasesDeletionLease`, original `AudioPlaybackTests.swift:46` |

`run-before.json` and `run-after.json` bind the source and fresh Mach-O artifacts to the run. Parameter cases replace their containing function in the expanded count. `native-network.log` contains the complete failure. The simulator's exit trap retained `wire-audit.json` when Swift returned exit 1. Independent inspection found zero peer violations. The protocol scenarios exercise production URLSession clients, two parallel ASR streams, incremental publication, persistent GPT WebSocket evidence and bounded same-model HTTP fallback. They use stateful local peers and synthetic audio. Real-account recognition quality and cloud latency remain unverified.

The independent debug playback experiment and the subsequent focused test correction have separate receipts under `playback-diagnostic`. The two passing tests in its corrected-source run belong to that later test change. The original local full result for 702a remains failed.

## CI results

[Native CI 42323923769](https://github.com/haohongfei2001-png/saytile/actions/runs/42323923769) and [design CI 42323923831](https://github.com/haohongfei2001-png/saytile/actions/runs/42323923831) both completed successfully on their first attempt. CI checked out merge `412e88cbabaca8be38031cd81addd9c767ff38d9`, with parents `4fa637a47ce869b7c7aade0ea7c0c121162e10ee` (PR #5 base branch) and this PR #6 head. The Git commit API reports the same `f5a357a00b97a246ee5c6ee0a95272738c135c0d` tree as the local runtime. `ci-merge-identity.json` preserves the exact relationship.

CI passed all **391 functions / 47 suites / 511 expanded scenarios** in 55.053 seconds. The original silent-playback case passed there. The same job passed its 50 localhost cases with zero violations, 97 AppModel checks, release build, 17 CLI guard cases, 7 setup cases, isolated startup and artifact upload. The render-only UI command produced **22 native captures** with zero AXPress. Its keyboard-isolation checks were 20 before validation, 20 after validation, 20 after interaction and 22 at capture. CI interactive AX controls remain `NOT_RUN`. `ci-snapshot.json`, `ci-native.log` and `ci-design.log` preserve the terminal workflow evidence and log hashes.

The CI result and local failure describe their respective executions. The cumulative count for this commit does not add CI, focused diagnostic or earlier baseline runs to the local suite total.
