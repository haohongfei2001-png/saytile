# Release-boundary transport verification

The local run used `69b90939fd688b35448f976950e96db0ce5b602a`, tree `06f1ac6982591bce64c98bd93e26eb0ccba0cfd8`. A fresh build passed 393 functions in 48 suites, covering 513 expanded scenarios. Swift Testing took 33.487 seconds after compilation. All 212 tracked engineering inputs matched their initial SHA-256 values. No tests were skipped.

| Measurement | Observed locally |
| --- | --- |
| Network suite | 12 functions and 52 expanded scenarios, including 50 actual loopback cases, zero peer violations |
| Parallel ASR input | Both clients sent identical 50 × 640-byte frames and an unpadded 198-byte tail, 32,198 bytes in total |
| VAD and delayed finals | The first WAV held 49,920 frames. Both old finals were held across VAD end and the next speech onset. The delayed final updated its original record while the next utterance stayed active |
| Four conversion rates | Complete waveforms matched at 16, 22.05, 44.1 and 48 kHz |
| Playback | Positive position 0.1288125 seconds appeared 0.150454708 seconds after play returned |
| Connection checks | Normal, WS-unsupported and churn cases each used two GPT requests. Reconnect used four, within the six-attempt budget |
| Unified output | The healthy case published three changing revisions and completed. The unsupported-selection case ended in the expected failed state |

These tests ran the actual Swift URLSession clients over localhost WebSocket and HTTP against controlled peers, covering PCM transmission, streaming changes, EOS, reconnect, HTTP fallback and publication. They do not measure provider-account access, human-speech accuracy, incremental quality gains or real-service latency. `run-before.json`, `run-after.json`, `native-network.log`, `driver.log`, `server.log` and `wire-audit.json` preserve commands, executable identities and raw results.

## GitHub Actions

Design CI succeeded. Native CI passed 393 functions in 48 suites, 513 expanded cases, 50 localhost cases and zero peer violations. GitHub cancelled the job during the separate AppModel step. Package build, CLI isolation, native UI, startup and final artifact upload were skipped. Its workflow conclusion is **cancelled**. CI produced zero interactive AX actions or native renders in this run. [Native run 42338255704](https://github.com/haohongfei2001-png/saytile/actions/runs/42338255704) · [Design run 42338255711](https://github.com/haohongfei2001-png/saytile/actions/runs/42338255711)

Both jobs checked out merge `ecad04185d9bbbe2881b947b85611dfb673f3781` with the same tree as the release head. The parents were the PR #5 base `4fa637a47ce869b7c7aade0ea7c0c121162e10ee` and this release SHA. The jobs and full logs are preserved in `ci-jobs.json`, `ci-merge-identity.json`, `ci-snapshot.json`, `ci-native.log` and `ci-design.log`. No manual rerun was requested. Local package and product checks have separate receipts. Prior candidates' CI and local results do not contribute to the counts here.
