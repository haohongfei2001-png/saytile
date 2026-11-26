# Chrome post-write editability read classification

## What is confirmed

Actions run `45530413100`, head `880840e`, failed Chrome's first insertion. The preserved original log records exactly one successful write (31 ms), a content/selection notification, and an otherwise identical target/caret/page snapshot with `editable=false`. Ownership was immediately invalidated. The next read was editable and the full AX text matched. This was a safe `unverified`, not a duplicate write.

The **original incident's property-level cause remains UNKNOWN**. Its log did not record whether AXRole was unreadable or AXEnabled explicitly returned false. No rerun replaces that failure.

The source nevertheless contains a reproducible classification defect: `string(... AXRole) ?? ""` turns a missing/failed role read into a definitive non-editable snapshot. Unlike the existing `unsupported` path for unreadable focus/range, this can never reach the finite read-only confirmation for the already-issued write.

## Minimal change

- Preserve absent/empty role as `NativeInputError.unsupported`; do not create a partial target snapshot from it.
- A known `enabled=false` remains definitive even if the role is also absent. A known non-editable role remains non-editable. Neither can be retried into success.
- Keep the existing optional AXEnabled compatibility behavior for known editable roles.
- Add content-free fixture reason labels: `editor-role-unavailable`, `editor-disabled`, and `editor-role-not-editable`. Future raw logs can distinguish the two hypotheses.
- Do not change `InputCoordinator.swift`, its four 220 ms settled-read checks, two complete witnesses after a gap, edit sequence, target/window/editor/page/caret/range/full-field proofs, or mutation/focus/send behavior.

## Validation

`InputRoleReadProbe.json`: **PASS 21/21** against the production policy, coordinator and isolated SQLite with simulated AX metadata. Nil/empty role recover only after fresh full proofs. Disabled, read-only, disabled-with-missing-role, persistent missing proof, insufficient proof, second content event, focus, layout, cancellation, process/window/editor/page/caret/selection/prefix/suffix/sensitive changes all refuse. Every scenario issues one mutation, rejects replay, and checks stored ownership.

Explicit denial is observed before the simulated successful write returns; a later readable snapshot cannot restore that binding. Nil and empty-role recovery take about 0.53 s under the unchanged budget, with five full-field reads including confirmation/ownership readback. These timings are fixture timings, not browser latency measurements.

`InputWitnessSettlementProbe.json`: **PASS 16/16**, unchanged prior cases including the Safari four-read budget with too few complete witnesses remaining a refusal.

The production Kit and both probes compiled locally. The expanded Swift Testing cases are committed but **NOT_RUN locally**, because this machine's established toolchain has no complete Xcode; unified final-SHA CI must execute them. **Real Chrome/Edge/Safari foreground acceptance is NOT_RUN here.** This patch fixes a demonstrated classification defect; it does not yet prove the original Chrome incident fixed.

No App, ASR, browser, keyboard, clipboard, or user data was used. The isolated compilation reused unchanged C objects from the prior recorded build; `build.json` records exact commands and Swift source hashes. It does not rebind any old runtime receipt to this new source.
