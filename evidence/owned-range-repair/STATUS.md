# Owned external range repair — 2026-11-07

Scope: `engine/owned-range-repair-20261107`, based on `59a63f2f77520ae684dd97c65417b90140fab342`. Parent integrates; no push, merge, installation or real target interaction. This slice implements the newly authorized exact-owned-range exception, not the old permanent-external-immutability rule.

## Implemented production path

- `NativeInputCoordinator` establishes one runtime owned range for the latest recording only after confirmed direct insertion, a byte-exact before/after field witness, valid contextual grapheme boundaries, and working focus/content observation. Existing user prefix/suffix are excluded from ownership. Contiguous confirmed suffixes extend that range. Manual reuse and unconfirmed insertions never acquire ownership.
- `publishFusion` preserves the append head and archive distinction. A separate correction head requires current complete required acoustic evidence, a full reviewed candidate manifest, validated source selections, and no unresolved/protected-content/audio-review conflict when revalidated without the old external prefix. Raw preview/agreement and a user draft cannot authorize repair. A complete reviewed correction becomes `acceptedProposal` for the GPT core, while `FusionPublication.revision` remains the old append head until external confirmation. Thus recognition can finish independently of pending external correction. No edit to SingleTranscriptEngine, GPT model or reasoning settings was needed.
- The AppModel direct-mode loop consumes the correction queue before normal independent appends. Pending corrections are journaled once per binding/revision and do not repeatedly attempt mutation or block later records. Target/selection change expires the binding; uncertain external outcomes require a fresh explicit binding before more automatic input.
- Store reserves a correction before either selection or text mutation. The coordinator and AX adapter recheck the binding, application/window/control/page, collapsed caret, byte-exact field witness and grapheme boundaries. Native mutation uses only `AXSelectedTextRange` followed by `AXSelectedText`; both must report settable. It rechecks the selected range and expected text immediately before the text setter, then verifies the resulting field and caret. No clipboard fallback, full-value setter, key event, Return, send or activation is used for correction.
- On confirmed repair, the corrected archive becomes the dispatch head, the logical prefix and owned range/caret are updated, and later delivery reserves only the new suffix. `cursors.end_utf16` retains its monotone insertion-ledger coordinate; corrected logical offsets come from `prefix`. Original dispatch text/ranges/revision IDs and the original overlap/no-rewind triggers remain intact, including for shortening corrections.
- Additive schema v4 creates `owned_input_ranges`, `owned_correction_heads`, and `owned_corrections`, with no data reset. The version gate prevents older code from interpreting the new cursor semantics. Restart invalidates all ownership/bindings and changes in-flight corrections to unverified. Audio-only deletion retains text/correction history; full record deletion erases the new text snapshots too.

## Boundaries and remaining acceptance

- **NOT RUN:** native AX interaction with any app, permission prompts, installed RC1, microphone, production preferences/database/audio, real credentials, paid APIs. The native adapter compiles but its selected-range behavior is not claimed as live macOS acceptance.
- Native repair needs complete focus/content observation, page observability for web controls, range reads, both setters, and an exact collapsed caret at the end of the owned range. Otherwise it remains pending. Reading a bounded field witness (maximum 65,536 UTF-16 units) is intentional to prove contextual grapheme boundaries and preservation of surrounding user text. That field witness stays in memory; only Saytile's own inserted text/offsets enter SQLite.
- A later recording insertion, user edit (including an observed edit/undo), page/control/focus/caret change, lost read/observer capability, or mismatching evidence prevents repair. Arbitrary older range relocation and multiple simultaneous owned records are deliberately unsupported.
- AX exposes no atomic compare-and-swap across processes. There are immediate pre-write checks and post-write verification, not a claim of editor-side transactional isolation. A timeout/failure after setting selection can leave the temporary owned selection or an uncertain replacement; the operation is consumed, ownership is invalidated, and no rollback/retry/clipboard action is attempted. Unsupported setters detected at preflight have no external side effect.
- Parent should run its unsandboxed synthetic fixture suite and, only under separate authorization, a dedicated native AX fixture. No real user app was used here.

## Evidence

Initial focused `OwnedRangeRepairTests`: **16 tests passed**, including parameterized 9 target-change cases and 7 evidence/ownership refusal cases. The suite drives production Store/coordinator with a fake OS adapter and isolated SQLite. One test additionally drives the actual `MultiRecognitionSession`/`SingleTranscriptEngine` with two fake ASR providers and a fake GPT decision boundary, through EOS, accepted correction, and replacement. Tests cover 50→500/emoji growth, shortening, preserved user prefix/suffix, duplicate suppression, new suffix after repair, unconfirmed initial insertion, stale evidence, user drafts/edits, selection-stage invalidation, durable pre-mutation reservation, crash/reopen, migration and deletion semantics. See `focused-tests.log`.

Complete native suite before the final session-state guard: **304 tests, 300 passed, 4 failed** (exit 1), not an all-green result. All 16 owned-range tests and all 23 existing input coordinator tests passed in this broad run. The four failures are outside the changed feature: both isolated synthetic Keychain tests threw `keychain(100001)`; both silent AVAudioPlayer integration tests threw `无法播放原音`. No real keys were read: the existing tests use unique `com.saytile.tests.credentials.<UUID>` services and dummy values. No microphone was started. See `full-tests.log`. The remaining unsandboxed fixture acceptance belongs to the parent; these failures were not retried or counted as passes.

All commands run from this worktree with scratch root `/tmp/saytile-owned-20261107`:

```sh
SAYTILE_TEST_SCRATCH=/tmp/saytile-owned-20261107/build \
SAYTILE_TEST_LOG=/tmp/saytile-owned-20261107/owned-tests.log \
CLANG_MODULE_CACHE_PATH=/tmp/saytile-owned-20261107/clang-cache \
SWIFT_MODULECACHE_PATH=/tmp/saytile-owned-20261107/swift-cache \
scripts/test-native.sh --disable-sandbox --filter OwnedRangeRepairTests

# Same scratch/cache settings; full-tests.log:
scripts/test-native.sh --disable-sandbox
```

The first build without `--disable-sandbox` was blocked by nested `sandbox-exec: sandbox_apply: Operation not permitted`; subsequent commands disable only SwiftPM's nested sandbox, not the task filesystem restrictions. Temporary test API/type compilation errors were fixed before the recorded passing focused run. The first full-engine fixture attempted to configure requirements after creating provider runs and was correctly rejected; the fixture now uses a fresh session with requirements frozen before provider creation.

Read-only remote preflight: PR #5 at `fbe9349b4799883c117f61d5afc7c62ab5c82936` had native FAILURE and data-and-prototype SUCCESS; PR #4 at `45af67049ddee2553fe1929a812aecb83cc157e4` had both SUCCESS. These are remote baseline observations, not validation of this local slice.


Production AppModel probe: **23 checks passed**, exit 0 (`app-model.log`), using the existing nonactivating fixture with isolated preferences and SQLite. This verifies existing draft/archive/exit behavior and compiles the changed direct loop; the probe itself does not bind an external target.

```sh
SAYTILE_MODEL_SCRATCH=/tmp/saytile-owned-20261107/build \
SAYTILE_MODEL_LOG=/tmp/saytile-owned-20261107/app-model.log \
SAYTILE_SWIFT_DISABLE_SANDBOX=1 \
CLANG_MODULE_CACHE_PATH=/tmp/saytile-owned-20261107/clang-cache \
SWIFT_MODULECACHE_PATH=/tmp/saytile-owned-20261107/swift-cache \
scripts/test-app-model.sh
```

Final review added a session-state gate: a correction approved before a cancellation, queued retry, failed expert/session or new recognition generation must no longer execute. The added parameterized regression covers all four states. The final focused run passed **62 tests** (exit 0), including all **17 owned-range tests** plus existing input, fusion-authority, dispatch and revision-safety tests; see `final-focused-tests.log`. Parameterized cases additionally cover 9 target changes, 7 evidence/ownership refusals and 4 terminal/generation states. The four environment failures above are not reattempted.


Final focused command (same scratch/cache environment as above):

```sh
SAYTILE_TEST_LOG=/tmp/saytile-owned-20261107/final-focused.log \
scripts/test-native.sh --disable-sandbox \
  --filter 'OwnedRangeRepairTests|InputCoordinatorTests|StoreFusionSafetyTests|storeDispatch|fusionRevision'
```

`git diff --check` passed. All pre-existing tests remain unchanged. Changed production files are limited to InputCoordinator, InputAccessibility, Models, additive Store/schema integration, and AppModel dispatch integration. AudioCapture, RecognitionAudioFanout, SpeechRecognition, MultiRecognitionSession, SingleTranscriptEngine, GPT transport/configuration, archive originals and other worktrees are untouched. Parent's next step is to integrate this local commit and run the unsandboxed synthetic fixture gate; actual native AX acceptance remains explicitly NOT RUN.
