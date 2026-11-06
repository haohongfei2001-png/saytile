> 最新集成交付见 [DELIVERY.md](DELIVERY.md)。下文是阶段性记录，不是最终能力清单。

# Single-transcript engine — 2026-11-07 checkpoint

**Partial implementation delivered; full requested scope is NOT complete.**

- Branch: `engine/single-transcript-completion-20261107`.
- Base: `a9cffae52d544b8a8939fce13d735b5ec1f2bc4f`; PR4 `45af670` ancestry verified. Remote PR5 had advanced; intentionally not merged.
- Engine milestone: `59a63f2f77520ae684dd97c65417b90140fab342`.
- Build-host fixes/candidate source: `41e4aae9911903f4797781c8311fcc59406a2d65`.
- No push, merge, PR mutation, installed RC1 operation, microphone, user-app activation, production-data access or cloud-model call. Parent's untracked PARENT_REVIEW.md left untouched.

## Implemented and exercised

Two complete-PCM ASR streams; exactly one per-recording/generation GPT WebSocket transport; latest-evidence coalescing and mandatory EOS review. Immediate ASR preview cannot certify new external ranges before GPT acceptance. Blocked GPT leaves capture/journal intact and cannot poll every 280ms. No second acoustic reviewer is called by the engine.

Transport tests cover manifest deltas/invalidation, lineage, lane/response filtering, partial JSON isolation, failed/incomplete responses, cancellation, timeout/buffer limits, credential/configuration cache invalidation and one full-context cache-miss recovery. Unsupported WebSocket fallback uses the same GPT HTTP client. No live-service verification or end-to-end latency claim. [Protocol reference](https://developers.openai.com/api/docs/guides/websocket-mode).

Migration preserves configuration IDs and custom models, never enables consent/cloud, and permits multilingual single-expert diagnostics with the same GPT. Apple SpeechAnalyzer now publishes Candidate/Store evidence. Physical PCM range retrieval crosses durable chunks, rejects nondurable tails, and caps each allocation at 1 MiB; no 12 MB lifetime buffer. The 13.44 MB test is accelerated synthetic audio, not a wall-clock soak. User drafts and existing no-replay ledger protections remain. Consumer revision/model-routing controls removed; evidence remains stored.

## Final verification

| Gate | Result |
|---|---|
| Restricted native Swift suite | **284 passed, 0 failed**, 35 suites |
| Production AppModel isolated probe | **23 checks passed** |
| Offline scoring / evaluation | **9 / 43 tests passed** |
| Candidate compilation, ad-hoc signature, ZIP integrity | **PASS**; Debug, not installed/launched |
| Two isolated Keychain tests | **BLOCKED**: status 100001 in this host |
| Two silent AVAudioPlayer tests | **BLOCKED**: unable to play in this host |
| Live cloud, microphone, native external patch, wall-clock soak | **NOT_RUN** |

Final native command: `SAYTILE_TEST_SCRATCH=/tmp/saytile-single-20261107-native SAYTILE_TEST_LOG=/tmp/saytile-single-20261107-engine/native-final-complete.log scripts/test-native.sh --disable-sandbox --skip-build --skip 'createReplaceReadDeleteKeepsAccountProviderAndServiceIsolation|invalidReplacementNeverErasesStoredDummyCredential|silentPlayerNaturallyFinishesWithoutStartingMicrophone|silentPlayerSeeksAcrossChunksAndReleasesDeletionLease'`.

PR5 run 42280700932 had 17 issues / 276 tests. Replaced obsolete five-service/acoustic-review and fast-mode test expectations with single-core and mandatory-review assertions; retained cancellation, deletion, evidence and ledger safety checks. Actual intermediate failures also included cache-miss retry on a closed socket (fixed), test fixture access level (fixed), nested SwiftPM/Clang cache denial (isolated scratch fix), and iconutil rejecting valid-size PNGs (ICNS fallback validated with macOS sips). Full private logs and hashes are indexed in RECEIPT.json; none are committed here.

## Candidate

`/tmp/saytile-single-20261107-candidate/Saytile-1.0.0-engine.single-transcript.1-debug.zip`

SHA-256: `10f6b4abe20baef1d52bda555c4a3d2534cd4d23ea219bb295a0f916787d9423`.

Bundle source is `41e4aae9911903f4797781c8311fcc59406a2d65`, dirty=false. Final evidence-only commit does not require rebuilding it.

## Remaining implementation / next slice

1. Exact external owned-range repair ledger and AX selected-range patch integration are **not implemented**. Corrections remain local; no duplicate append or whole-field replacement was added. Existing fake-input tests are not evidence of native correction support.
2. Optional Apple evidence alongside cloud and automatic network-to-local failover are **not implemented**; capture/journal and queued recovery remain available. Local ingress is tested with synthetic events, not actual microphone/SpeechAnalyzer recognition.
3. Legacy standalone acoustic adapter helpers still compile for compatibility/testing, but the coordinator has no call path to them. No claim of complete removal beyond the engine path.
4. Full native OS gates above and real cloud protocol/quality/latency remain separate acceptance work. Remote CI was not rerun because pushing is prohibited.
