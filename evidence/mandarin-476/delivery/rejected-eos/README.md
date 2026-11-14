# Rejected isolated EOS token-verification experiment

**REJECTED / NOT ADOPTED. Shipping 0.13 (476) is unchanged.**

The experiment cloned the already-verified 476 host (`0fbca1d892bbc8aa550c4439b8cfcb045af825ae`) and changed only its worker to recompute full current PCM at eligible EOS using token-ID proposals checked against the current causal decoder. It did not promote a preview string into a final transcript. The independent static review found no concrete structural state/ownership flaw but explicitly warned that multi-token computation can change floating-point logits and final words. The same-audio run confirmed that risk.

## Quality decision

| Cohort | Shipping 474 and 476 | Experiment | Change |
| --- | ---: | ---: | ---: |
| Public 420, CER errors / reference units | 910 / 10,663 (8.534%) | 914 / 10,663 (8.572%) | +4 errors |
| Derived 20 | 65 / 764 (8.508%) | 65 / 764 (8.508%) | none |

All 440 archives were nonempty; observed provider remained `qwen-small`. Thirteen complete texts changed: 5 clips worsened, 3 improved, 5 had equal CER. Scoring, WAV hashes and reference text were unchanged. Existing incomplete VAD subsegments remain counted.

The changed text includes a correct currency country term **刚果法郎 → 干国法郎**. Improvements include `Sepulvada → Sepulveda`; other changes include names, `掠食者 → 猎食者`, an added `的` inside English text, and an added `儿`. No changed normalized span contained a number or negation character under the simple review flagger, but that flagger is not a complete semantic/critical-entity test. Every changed record, reference and score is retained in `quality-review.json` for direct inspection.

The initial runner's `accuracy_gate` records its conservative per-clip screen. It is not a user-mandated requirement that every sample must match or improve. The final root decision in `decision.json` rejected the actual **net CER and currency-entity regression**. The planned original-rate follow-up was canceled after this decision. No new speed claim or product adoption is made.

## Evidence and provenance

- `bench-identity.json`: explicit `EXPERIMENTAL_DIRTY_WORKER`, host source, normalized host-code equality, actual helper/patch SHA, unchanged compiled Cohort hash.
- `manifest.json`, `eos-experiment.patch`, `source/`, `build.py`, `build.log`: experimental build provenance. Relevant unchanged Qwen decoder source is retained with its runtime license; complete upstream/base dependency context remains at source SHA above.
- `STATIC-REVIEW.md`, `static-review.json`: independent source review before quality acceptance; its compile success is not a quality pass.
- `raw-440.zip`: original per-shard output/logs, merged 440 rows and complete execution log. The initial preflight rejection was only a signature-normalizer check; no ASR started during that rejection. The retry compared all non-signature Mach-O bytes and load commands, allowing only code-signature and __LINKEDIT size changes caused by ad-hoc re-signing.
- `references/`: same 440 manifest references plus independently verified WAV hashes.
- `comparison.json`: unchanged scoring against **both** 474 and 476, including all positive and negative differences.
- `quality-review.json`: complete reference texts, old/new output, normalized edit spans, individual score deltas and conservative review flags.
- `tools/`: actual run and review scripts.

Accelerated PCM may reach EOS before any draft exists. Therefore this corpus does **not** prove every sample exercised EOS token verification. Actual branch coverage would require a final decode with `verifiedPreviewTokens > 0` under original-rate replay; that additional compute was not performed after rejection. This limitation does not erase the observed final-output regressions.

Only licensed public/derived WAVs and fresh temporary SQLite/audio paths were used. No private audio, paid service, production installation, existing user archive or committed product source was changed. The experimental App was not installed. All GPU work ended and no further experiment was started.
