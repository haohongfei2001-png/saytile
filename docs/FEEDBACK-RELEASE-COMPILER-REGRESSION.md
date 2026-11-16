# Feedback release compiler regression

Baseline: `b6b35126d46dc0fc2bec24211e5bafa3708c6ad0`.

The native CI release build failed with `<unknown>:0: error: circular reference` while compiling the app. The feedback library itself built successfully. A local replay of the failing SwiftPM command with `-Xfrontend -debug-cycles` identified the exact request cycle:

```text
ExecuteSILPipelineRequest(
  Run pipelines { PrepareOptimizationPasses, EarlyModulePasses,
  HighLevel,Function+EarlyLoopOpt, HighLevel,Module+StackPromote }
  on SIL for SaytileApp)
  ActorIsolationRequest(RiftletFeedback.(file).FeedbackStore.deinit)
  ===CYCLE DETECTED===
```

This is an imported isolated actor destructor encountered during release optimization. It is not a feedback-view, SwiftUI state-wrapper or test-fixture inference. The diagnostic replay eventually exited with signal 11; the original CI and local release builds emitted the circular-reference error and failed normally.

The fix retains actor-exclusive SQLite access and moves the connection and process-lock lifetime into a private resource-owning class. Its ordinary destructor closes both resources after the store is released. The initializer's error cleanup and explicit close remain unchanged. No `unchecked Sendable`, lower optimization level, test exclusion or UI rewrite was introduced.

Controlled local comparison used Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), target `arm64-apple-macosx26.0`, Swift 6 language mode, `-O`, `-whole-module-optimization`, and the same complete app sources, Sparkle framework, and previously compiled SaytileKit/SaytileVoiceUI modules. Only the imported feedback module and output location changed:

| Check | Original isolated actor destructor | Private resource owner |
| --- | --- | --- |
| Feedback module release compilation | PASS | PASS |
| Full app release module emission with cycle diagnostics | FAIL: destructor request cycle | PASS: exit 0 |

The local comparison establishes the compiler-cycle fix, not a replacement for the final full release build and CI. The new lifecycle tests exercise automatic destructor cleanup without calling explicit close, exclusive process locking, retained drafts after reopening, idempotent explicit close, and initialization failure followed by successful reopening. Existing outbox and controller assertions remain intact.

The parent agent additionally completed a fresh full native SwiftPM **Release/WMO executable build** with the repaired source: PASS (184.88 seconds), including final linking. Core tests passed 6/6, and the actual controller compiled at `-O -whole-module-optimization` and passed 12/12. Final remote CI remains a separate exact-commit check.
