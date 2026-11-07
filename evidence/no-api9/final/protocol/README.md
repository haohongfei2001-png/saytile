# no-api.9 source and transport verification

The local Mac built `dc26fe3c59ba55994d29e99ada8d2f0b49ad9886`, tree `f138f6733a642a2e53da22b3647aaf5744cb308b`, in a fresh build directory. All 393 Swift test functions in 48 suites passed, covering 513 expanded scenarios and zero skips. Testing took 33.634 seconds after compilation. The 212 tracked engineering inputs and source tree matched before and after the run.

| Measurement | Local result |
| --- | --- |
| Wire protocols | 12 functions, 52 expanded scenarios, 50 actual localhost peer cases, zero protocol violations |
| PCM streams | Both ASR clients sent the same 50 × 640-byte frames and unpadded 198-byte tail, 32,198 bytes total |
| Audio conversion | Complete outputs matched at 16, 22.05, 44.1 and 48 kHz |
| VAD and delayed finals | The first WAV held 49,920 frames. Both old expert finals remained held across quiet and new speech onset. A late final updated its original record while the next utterance remained active |
| Playback | Positive position 0.1115 s was observed 0.134394292 s after play returned |
| Connection checks | Normal, WS-unsupported and churn cases used two GPT requests. Reconnect used four within the shared six-attempt limit |
| Unified text | The normal case produced three changing revisions. Unsupported selection ended in the expected failed state |

Production URLSession clients exchanged binary PCM, incremental events, EOS and review requests over actual WebSocket and HTTP connections to controlled peers. The scope is `SIMULATED_PROTOCOL_NOT_LIVE_CLOUD`. Provider-account connectivity, human-speech accuracy, comparative fusion gains and real confirmation latency remain unmeasured. `run-before.json`, `run-after.json`, `driver.log`, `native-network.log`, `server.log` and `wire-audit.json` retain source and binary hashes and raw transport evidence.

## Exact-head CI

Both GitHub Actions workflows succeeded. The native job passed 393 functions in 48 suites and 513 expanded cases in 58.209 seconds, with all 50 network cases and zero peer violations. AppModel 104, package build, CLI isolation 17 + 7, native rendering, isolated startup and artifact upload also passed. CI rendered 27 routine captures and 3 approved-reference captures. It recorded 28 key/main isolation checks at each before-validation, after-validation and after-interaction stage, and 30 at capture. It used render-only mode, with zero interactive AX actions. [Native run 42340210171](https://github.com/haohongfei2001-png/saytile/actions/runs/42340210171) · [Design run 42340210183](https://github.com/haohongfei2001-png/saytile/actions/runs/42340210183)

Both jobs checked out merge `833a3f3f00dfcc219bed5fa81e040773c069fab1`, with the same tree as the frozen source. The parents were the PR #5 base `4fa637a47ce869b7c7aade0ea7c0c121162e10ee` and this PR head. The job snapshots, raw logs and Git tree identity are in `ci-jobs.json`, `ci-snapshot.json`, `ci-merge-identity.json`, `ci-native.log` and `ci-design.log`. No workflow was manually retriggered.
