# 0.23（569）experience prototype — Draft / HOLD

Product source: `5ebff045ff10c34dbbe12ce5235e3cef4f6d07a0`.
Branch: `codex/experience-preview-023`; Draft PR #54, based on PR #53.

Authoritative result: [STATUS](../../docs/delivery/experience-023/STATUS.md), [ACCEPTANCE](../../docs/delivery/experience-023/ACCEPTANCE.md), [ARCHITECTURE](../../docs/delivery/experience-023/ARCHITECTURE.md).

- `setup/`: pinned model card, SHA-256 checks, fixed manifests, contaminated-run disclosure and original download failure.
- `native/`: original 0.22 / provisional 568 / Nemotron auto-prompt observations; first three contaminated timings retained and repeated in `repeated4`.
- `replay/`: identical raw candidates through both publication policies. No new inference or invented words.
- `final/paired16/`: signed 569, explicit-model two-route real-rate comparison, fifteen clips plus 38.8-second long fixture. Owned-view PNGs included.
- `final/product440-*.jsonl`: full product quality; original 420 plus separately scored 20 variants.
- `final/soak-*.json`: 905-second native use, original audio checksum, SQLite integrity, idle unload/resume.
- `final/variance/`: three paired observations per selected case, 17 complete + 1 failed. Failed visible final retained, never skipped or retried into PASS.
- `final/surface-replay.json`, `window-diagnostic/`: bounded diagnostic follow-ups, not proof that the original observation failure was repaired.
- `final/ci*`, `foreground/`, `failures/`: same-product CI and retained earlier failures.
- `final/package.json`: exact signed binary, DMG hash, Gatekeeper rejection, isolated offline launch and unchanged installed 533 hash.

Qwen is the better tested Chinese route: 15-clip CER 8.10%, full 420 CER 8.53%. Nemotron explicit Chinese: 32.75% / 25.44%; not promoted to the consumer default. Provisional previews improve long-utterance waiting but increase some old-word oscillations; first-output non-regression remains FAIL. Five old failed empty subsegments remain failed and retryable with audio, not relabeled completed.

No installation, notarization, merge, public release, private audio access, paid API calls, or change to main/533. Live microphone and real cloud service verification remain NOT_RUN.
