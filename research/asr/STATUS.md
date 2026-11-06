# Saytile ASR research — resumed 2026-11-06

## Scope and baseline

- Production base verified against origin/main: `a352a1c812c33388a1a908f21ecde30da80ad1cd` (RC1 / merged PR #3).
- Independent branch: `research/asr-quality-2026-11-06`.
- RC1 production source, installed application, personal recordings and databases are not modified.
- Goal: matched human-audio direct-ASR vs actual-production-VAD evaluation, bounded cloud comparisons when already authorized credentials exist, and evidence-based implementation decision.

## Recovered, not recreated

- Prior working tree: `/workspace/scratch/ecf2608272fb/saytile-research`.
- Prior local checkpoint `ef2730b` and uncommitted research files survive.
- `research/asr-2026-11-06/` is preserved as the original research record.
- 134 WAV files exist at `.test-data/asr/audio/`; manifests and metadata are recovered. Integrity and licensing are being independently checked.
- Prior Whisper output currently contains 15 successful rows; it is incomplete, not a completed benchmark. Failed PyAV decoding attempts are retained separately.
- Connected Mac research directory exists at `~/.codex/saytile-asr-research-20261106`; Qwen3-ASR-1.7B BF16 MLX weights and Python environment survive.
- A partial base64 transfer file exists on Mac. It is not used to claim a completed corpus transfer, and that transport method is discontinued.

## Evidence status

- Cloud model comparisons: NOT RUN. No ASR keys present in this process environment; checking narrowly scoped existing authorized configurations without exposing secrets.
- Apple direct and production-VAD matched evaluation: NOT YET RUN in this resumed session.
- Real-time latency: NOT YET MEASURED. Offline processing time is not first-word latency.
- Global best-engine claim: NOT ESTABLISHED.

## Work in progress

1. Verify original corpus files, selection, licenses, hashes, and scoring.
2. Recover Mac execution environment and download source archives directly on Mac, with pinned revisions and hashes.
3. Run original Apple baseline, language-selected diagnostic, Qwen local reference and Whisper on matched samples.
4. Replay the actual production VAD/splitter; compare transcription and boundary losses.
5. Run bounded existing cloud services if credentials are available; record blocked providers explicitly.
6. Measure paced latency and decide whether a second recognition stage has demonstrated benefit.
7. Persist each completed phase, implementation contracts, limitations, and PR.

All audio remains outside Git. No new paid service is opened. No binary audio is transported through chat/tool text.
