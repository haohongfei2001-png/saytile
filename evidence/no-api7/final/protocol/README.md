# no-api.7 source and transport verification

The local run of `4b97bd89b258fea29a0be61d4bd4c23cb5ab428c`, tree `4aac670d6edfcce0c12ed22fa3cd5c68e66061b9`, passed 392 Swift test functions in 48 suites. The 512 expanded cases include parameterized inputs. Swift Testing reported 33.533 seconds after compilation and zero skipped functions. All 211 tracked engineering inputs matched their pre-run hashes. The source, executable and test bundle identities are in `run-before.json` and `run-after.json`.

| Observed on the local Mac | Result |
| --- | --- |
| Protocol tests | 12 functions, 52 expanded scenarios, 50 localhost network cases, zero peer violations |
| Two simultaneous ASR streams | Both received the same 50 × 640-byte PCM frames and 198-byte final fragment, 32,198 bytes total |
| VAD with delayed expert finals | The first WAV held 49,920 frames. Both expert finals were still held when quiet and the next utterance were observed. The old final updated its original record while the next utterance remained active |
| Audio continuity | Waveforms matched reference conversion at 16, 22.05, 44.1 and 48 kHz |
| Playback | The first positive progress event was 0.0985 s at 0.119556416 s after play returned |
| GPT connection and publication | Normal, WS-unsupported and churn checks used two requests. The reconnect check used four within the six-attempt limit. The healthy engine case produced three visible revisions. An unsupported candidate selection ended in the expected failed state |

The production URLSession clients exchanged actual WS frames, PCM and HTTP responses with a local simulator. The run exercised EOS, persistent review, bounded reconnection, candidate protection and same-model HTTP fallback. Account availability, real-provider recognition accuracy, fusion gain and latency remain unmeasured. The command, individual assertions, server interactions and per-case audit are preserved in `run-before.json`, `native-network.log`, `driver.log`, `server.log` and `wire-audit.json`.

## GitHub Actions

For the frozen head, native CI passed 392 functions in 48 suites, 512 expanded cases and all 50 localhost cases. GitHub then cancelled the job during `scripts/test-app-model.sh`. Package build, CLI isolation, rendering, startup and final artifact upload were skipped. The native workflow conclusion is **cancelled**. Design CI succeeded. Both checked out merge `24fe94b73da71a33cd6115d1abfc1feb68a86b40`, whose tree matched the frozen source. [Native run 42333550192](https://github.com/haohongfei2001-png/saytile/actions/runs/42333550192) · [Design run 42333550200](https://github.com/haohongfei2001-png/saytile/actions/runs/42333550200)

The next commit, `54b4c40fea85069ee77c60fd414bfab8f535c8fb`, changed two design documents. Its full tree is `8b5efa4eab48db698f9072d39c65fbcd81d447b5`. Sources, tests, scripts, package metadata, contracts, packaging and workflow files were unchanged. Both successor workflows succeeded on merge `3f3708205fca38c9b5a1e50b2aa52571c91cecaa` with that successor tree. The native job passed 392 functions, 512 expanded cases, 50 localhost cases, AppModel 104, CLI guards 17+7, startup and artifact upload. CI rendered 27 captures. Interactive AX controls were unconfigured in the CI render run. Both CI merges used the PR #5 base branch parent `4fa637a47ce869b7c7aade0ea7c0c121162e10ee`. [Successor native run 42333775516](https://github.com/haohongfei2001-png/saytile/actions/runs/42333775516) · [Successor design run 42333775472](https://github.com/haohongfei2001-png/saytile/actions/runs/42333775472)

The top-level CI logs and job receipts are the frozen head’s records. `docs-successor-ci/` contains the separately identified successor logs, checkout metadata and engineering-input comparison. No workflow was manually retriggered.
