# 0.23 experience prototype — IN PROGRESS / HOLD

Independent branch `codex/experience-preview-023`, based on PR53 `0ba33940788ff3b74af38c6f24e47d4e5c1afeba` (product `a90601b`). PR52 and installed 0.20(533) remain unchanged.

Scope: existing Qwen 0.6B vs Nemotron 3.5 MLX 8-bit only, same public 15 wall-paced and 420 corpus. No new ASR, Metal experiment, private recordings, installation, notarization or release.

Prototype: bypass only the whole-hypothesis *reading* gate for provisional rolling Qwen previews. Same-length isolated tail flips still require another observation. Every preview is the actual model hypothesis (except the existing terminal-period suppression); zero dispatch length until final. Existing Store ownership, raw audio and user edits stay protected. Partial text uses a lighter ink; final/user-edit text remains normal ink. The 0.22 gate remains available solely for exact offline paired replay.

Model download fixed to existing manifest and SHA-256; one small-file TLS failure retained in setup/download-first-attempt.log, followed by a bounded retry. Never enable unchecked partial weights.

NOT_RUN: current prototype native acceptance, corpus comparison, CI. Mac lid stays closed; live microphone NOT_RUN. P2 artificial 5.33-core stress is not this prototype's only product gate.

## Confirmed adapter defect
The pinned Nemotron `languages.json` has `zh-CN:4`, `zh-TW:5`, `auto:101`, and no `zh`. Upstream `NemotronLanguages.slot(for:)` silently falls back to auto for the existing `createSession(language:"zh")`. Both initial and reset sessions now use the explicit available `zh-CN`; a missing tag fails configuration. Original auto-prompt real-time results remain in `native/paired16` and `native/repeated4`. They are pre-fix evidence, not the corrected model's score.

0.23(568) prototype product SHA `d68c43a` is signed and native-tested. The only later changes before the adapter correction were tests/tools/evidence; a rebuild refused to overwrite its custom path, leaving that bundle unchanged. 0.23(569) will contain the explicit-language fix. No production installation.
