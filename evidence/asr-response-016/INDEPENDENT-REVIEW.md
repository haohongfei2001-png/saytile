# 0.16 (486) source and adoption review

Reviewed product SHA: `d0b2d87320fd4145fbaea756690066bca3718bab`; installed control: `ab8545507c79640ec3f419e33467a0263c154844` (0.15/484). Read-only review of the complete diff and the source-bound native receipts. No ASR, microphone, cloud calls or compilation were run for this review. The reviewer previously contributed the publisher change and its tests; this is a separate evidence review, not an assertion of completely independent third-party authorship.

**Recommendation: retain installed 484; do not automatically replace it with 486.** Preserve the narrow correctness fix and candidate in Draft PR #42. The code fixes a real evidence-delivery mismatch, but the measured package has not established an overall responsiveness or resource improvement. No newly identified P0/P1 defect in this diff justifies overriding that adoption result.

## Source assessment

- **PASS — actual observations and order.** Worker.swift:155–162 forwards each real Qwen decode, including unchanged words over more PCM. It does not add inference calls or manufacture text. LocalASRProvider.swift:210–217 retains protocol order validation and always supplies actual frames. The publisher rejects same-frame Qwen partial retries and regressing frames before altering corroboration state. An unchanged final at the current frame still completes. Equal-frame streaming-provider updates remain permitted.
- **PASS — no new lost-final or repeated-text path found.** Already visible Qwen duplicates return before Store/notification publication and preserve provisional punctuation. A return to the prior visible wording clears an intervening unconfirmed correction. New audio confirming an otherwise withheld whole hypothesis can be admitted under the existing lexical/number/negation checks. Those checks were not relaxed. Qwen partial stable UTF-16 length stays zero; the scalar final path is unchanged.
- **PASS within reviewed scope — user edits and data boundaries.** This diff does not change capture, VAD, PCMJournal, SQLite, selection ownership or external dispatch. Store.swift:1347–1348 still excludes selected user-edit revisions and active editing drafts from automatic preference replacement. The production ingress continues through the same ticket/Store gate. This is source review plus existing regression evidence, not a new personal-archive test.
- **PASS — tests strengthened, not weakened.** Four new Qwen tests cover independent observations, repeated/regressing frame rejection, correction-pair reset and streaming compatibility. The prior pause test now first proves that the first tone started VAD; it retains the 1.1-second pause and one-start/one-end assertions. No test was skipped or existing safety assertion lowered. The recorded full CI log contains 528 passing Swift test functions across five isolated invocations (4 + 13 + 12 + 8 + 491), and the five check states are SUCCESS. The separate local 31-test and 5-test runs agree.
- **No decoder-CPU saving established.** Additional Qwen IPC/JSON observations incur some handling overhead, but already accepted duplicates are filtered before database work. There is no additional recognizer or decode loop. Resource behavior must be judged from actual packages, not this small source diff alone.

## Measured adoption decision

Source: [clean paired report](paired/FINAL-SUMMARY.json). Every one of 18 matched final archives is identical, and all 36 raw-final/archive/window comparisons agree. This proves preservation for these fixed public samples; it does not prove universal no-missing-word behavior.

| Metric | 484 | 486 | Interpretation |
|---|---:|---:|---|
| 15 original-rate clips, CER | 46/568 (8.10%) | 46/568 (8.10%) | Preserved, not improved |
| Two reference-bearing extended clips | 36/297 (12.12%) | 36/297 (12.12%) | Preserved; not a population ranking |
| First visible matching text P50/P95, 15 clips | 0.955/1.551 s | 1.054/2.805 s | Candidate observation is worse; cause not isolated |
| Useful display-update interval P95, 15 clips | 1.016 s | 1.026 s | No demonstrated win |
| Stop to eventual-final display P95, 15 clips | 2.850 s | 2.794 s | Small difference, not a proven endpoint improvement |
| App + helper CPU, two 38.8 s runs | 12.16 / 12.82 CPU-s | 12.29 / 12.03 CPU-s | Overlapping variation, no reliable saving |
| Simultaneous physical-footprint peaks | 1687.9 / 1673.7 MiB | 1815.2 / 1800.8 MiB | Higher candidate footprint in both paced pairs |

The [fixed-PCM resource control](resource/fixed-pcm/RESOURCE-ATTRIBUTION.json) produced identical 16 partials and nearly equal CPU (3.20/3.19 s) and global peaks (1798.986/1798.423 MiB), but candidate intermediate footprint remained higher at several identical audio boundaries, up to 417.094 MiB. This single control does **not** establish allocation-lifetime equivalence or dismiss the two native peak differences as harmless timing. There is no basis to claim a CPU/memory win or automatically install the candidate as a performance upgrade.

## Limits and rejected experiments

The separate 50- and 60-frame endpoint trials both changed the money phrase `现金` to `现今`; neither belongs in this product candidate. Keep the existing 75-frame production threshold. Do not trade that semantic regression for faster final confirmation.

Physical microphone is NOT_RUN by the user's clamshell instruction. Natural personal speech, an 8 GB Mac, energy/GPU/ANE measurements and universal onset/tail preservation remain unverified. Existing long-sentence and stop-response limits remain real; test/CI success does not resolve them. These limits should accompany the candidate rather than be hidden by an automatic replacement of 484.
