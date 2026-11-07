# Formal no-api.6 source verification

The local full Swift run for `455143310222c2c03c4a4888e5df5552c3af4131` passed **392 functions in 48 suites**, comprising **512 expanded scenarios**. Swift Testing took **33.215 seconds** excluding compilation. All 211 tracked engineering inputs, HEAD and tree matched before and after execution. The new scratch directory was `/tmp/saytile-official-noapi6-native-45514331`. The executable and test-bundle Mach-O hashes are in `run-after.json`.

| Boundary | Local result |
| --- | --- |
| Runtime tree | `87015ba6c1cb2b38c5a868a2fed1b86b9eaac683` |
| Provider protocols | 12 functions / 52 scenarios, 50 actual localhost network cases, zero contract violations |
| Audio chunks | Both production ASR clients received the same 50 × 640-byte frames and 198-byte tail, 32,198 bytes total |
| VAD and delayed finals | The first WAV contained 49,920 frames. Both expert finals remained held through VAD end and new speech onset. The late final updated the first record and the second remained active |
| Playback progress | Positive position 0.108375 seconds appeared 0.129828625 seconds after `play` returned. Chunk seeking, deletion lease release and retained text passed |
| Connection checks and publication | Normal, unsupported-WebSocket and churn cases used two GPT requests. Reconnect used four within the shared six-attempt cap. The normal engine run published three changing revisions. The unsupported selection was rejected |

The command was `SAYTILE_SIM_FULL_SUITE=1 SAYTILE_SIM_EVIDENCE=evidence/bottom-controls/final/protocol SAYTILE_TEST_SCRATCH=/tmp/saytile-official-noapi6-native-45514331 scripts/test-protocol-simulator.sh`. `native-network.log`, `driver.log`, `server.log` and `wire-audit.json` retain the raw results. Parameterized scenarios replace their corresponding function in the expanded count.

Qwen, AssemblyAI and GPT transports used production URLSession code, actual localhost sockets and controlled peer responses. The suite covers WS handshakes, binary PCM, interim results, EOS, persistent GPT review, bounded reconnect and same-model HTTP fallback. Its scope remains `SIMULATED_PROTOCOL_NOT_LIVE_CLOUD`. Live account access, recognition accuracy, fusion gain and provider latency require real-provider evidence.

## CI results

[Native CI 42331341272](https://github.com/haohongfei2001-png/saytile/actions/runs/42331341272) and [design CI 42331341221](https://github.com/haohongfei2001-png/saytile/actions/runs/42331341221) both succeeded on their first automatic attempt. The checkout merge was `63a61ae3d33f8b871f3d0235d35ea130df4cbdc7`, with parents `4fa637a47ce869b7c7aade0ea7c0c121162e10ee` (PR #5 base branch) and the supplied PR #6 head. The Git commit API confirms the same `87015ba6c1cb2b38c5a868a2fed1b86b9eaac683` tree. Full logs and job/step receipts are in `ci-native.log`, `ci-design.log`, `ci-snapshot.json` and `ci-merge-identity.json`.

CI passed **392 functions / 48 suites / 512 expanded scenarios** in **56.315 seconds**. It also passed all 50 localhost network cases, 104 AppModel checks, release build, 17 cloud-probe guard checks, 7 setup guard checks, startup and artifact upload. It observed positive playback position **0.2504375 seconds** after **0.274127583 seconds** from `play` return and the same 49,920-frame VAD/late-final boundary.

CI rendered **27 native captures**. Key/main capability and actual state remained false in 25 before-validation, 25 after-validation, 25 after-interaction and 27 capture checks. Outside foreground transitions counted zero. CI interactive AX controls have status `NOT_RUN`, matching the render-only invocation and zero AXPress. The package's local interactive checks have their own receipts.
