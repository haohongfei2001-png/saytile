# Frozen 24-clip single-ASR + GPT-6 comparison

Current production architecture: one ASR expert per recording plus one GPT-6 Astra text core. The earlier A-E multi-expert comparison is superseded. Historical `prepared/` and `not-run-summary.json` receipts remain immutable evidence of the old plan; do not use them as current instructions.

## Current experiment

- A: Qwen Audio 3.1 Message + GPT-6 Astra (Chinese candidate)
- B: AssemblyAI Universal-3.6 Pro + GPT-6 Astra (English candidate)
- C: Soniox STT v6 + GPT-6 Astra (Chinese-English mixed candidate)

Use the same frozen 24 audio IDs, hashes, reference text, context rules, GPT configuration, and scoring. Each run sends the complete audio to exactly one ASR. Total maximum: 24 × 3 = 72 complete pipeline runs. A/B/C are independent runs; no audio fanout, no mid-recording provider switch, no retry-to-success that drops failures.

Record raw ASR accuracy and GPT final accuracy separately, GPT-introduced and GPT-repaired errors, critical numeric/amount/time/negation/terminology errors, Chinese CER, English WER, mixed MER, first-visible-text and final-confirmation latency, API request count, provider usage and actual cost. Unavailable usage stays unknown. Failed or unresolved runs remain in the denominator and are not scored as perfect.

## No-key status

No API credentials or paid authorization are available. A/B/C are `NOT_RUN`; no cloud calls or audio uploads are performed. `prepared-single-asr-gpt6/` is the current prepare-only command/config snapshot. The old `prepared/` directory is retained as historical evidence and is superseded.

Run offline tests with:

```sh
python3 -m unittest discover -s research/asr/benchmark/single-transcript-2026-11-07 -p 'test_*.py' -v
```

The evaluator proves trace identity and full PCM delivery using submitted frame count, input EOF, provider/session terminal evidence and generation/configuration identity. Last-word acoustic end time is not a PCM coverage test: trailing silence is valid.
