# 0.23 experience prototype — IN PROGRESS / HOLD

Independent branch `codex/experience-preview-023`, based on PR53 `0ba33940788ff3b74af38c6f24e47d4e5c1afeba` (product `a90601b`). PR52 and installed 0.20(533) remain unchanged.

Scope: existing Qwen 0.6B vs Nemotron 3.5 MLX 8-bit only, same public 15 wall-paced and 420 corpus. No new ASR, Metal experiment, private recordings, installation, notarization or release.

Prototype: bypass only the whole-hypothesis *reading* gate for provisional rolling Qwen previews. Same-length isolated tail flips still require another observation. Every preview is the actual model hypothesis (except the existing terminal-period suppression); zero dispatch length until final. Existing Store ownership, raw audio and user edits stay protected. Partial text uses a lighter ink; final/user-edit text remains normal ink. The 0.22 gate remains available solely for exact offline paired replay.

Model download fixed to existing manifest and SHA-256; one small-file TLS failure retained in setup/download-first-attempt.log, followed by a bounded retry. Never enable unchecked partial weights.

NOT_RUN: current prototype native acceptance, corpus comparison, CI. Mac lid stays closed; live microphone NOT_RUN. P2 artificial 5.33-core stress is not this prototype's only product gate.
