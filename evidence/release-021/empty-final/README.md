# Five empty finals: source and acoustic boundary investigation

All five failed WAVs were recovered from the prior owned fixture directory.
Their SHA-256 matches the original failure manifest. Every Int16 PCM frame is
an exact contiguous slice of the pinned FLEURS whole WAV: no dropped samples,
new padding or rewritten denominator. `alignment.json` records offsets/hashes.

| Public clip suffix | Failed slice, seconds in original | Independent Apple recognized speech | Qwen original / diagnostic gain | Disposition |
|---|---|---|---|---|
| e0687aaa8689e196 | 17.18–18.48 | 3.60–16.32 | empty / empty | failed, audio retained |
| fd242859bc18ffbb | 0.00–4.52 | 7.68–17.28 | empty / empty | failed, audio retained |
| c1fcf0cd023db10f | 0.00–2.44 | 3.60–13.44 | empty / empty | failed, audio retained |
| b53a7292b38e011d | 10.48–12.90 | 1.86–9.60 | empty / empty | failed, audio retained |
| 9a0d49266d4f5e24 | 13.12–15.00 | 3.60–12.48 | empty / empty | failed, audio retained |

**Confirmed:** the failed inputs are before or after the independently
recognized full reference sentence, with zero overlap. Apple transcribes the
whole sentences but rejects all five fragments with `RecogRejected`. Qwen
recognizes each full sentence, returns empty on the original fragments, and
still returns empty when their gain is raised (peak capped at −1 dBFS). The
gain experiment is diagnostic only, not product preprocessing. Two-second
context expansion sometimes returns adjacent sentence words; those words are
outside the failed slice and are NOT a recovered transcript for that slice.

**Likely cause:** non-speech energy at the leading/trailing edge triggered the
unchanged WebRTC VAD. This is not evidence of lost reference words. The source
timestamps name the first detected activity; PCM pre-roll explains why those
timestamps differ from the exact file offsets. Original RMS values are −62.94
to −49.50 dBFS. Low level alone was not used to classify the samples.

**Remaining uncertainty:** this investigation did not listen to the clips or
obtain human speech labels. Two recognizers and their timing do not certify
absolute silence. Therefore no completed/no-speech state is manufactured. All
five remain failed and retryable, with all original audio retained. The full
420 denominator and original failed records remain unchanged.

**Product correction:** distinguish worker EOS with empty text from a missing
EOS. Previously both reached `ProviderFailure.incomplete`, falsely reporting
that the model had not finished. Empty EOS now reports “未识别到文字，原音已保存，可回听或重新识别。”
If a partial exists, it explicitly says that final text was unavailable and
keeps the partial/edit. This neither restarts the healthy worker nor suppresses
the recording, changes VAD, dispatches uncertain text or modifies final words.

Evidence: `diagnosis.json`, `qwen-diagnostic.json`, Apple whole/fragment JSONL,
and `apple-ranges.json`. The probe's initial missing-resource-reservation result
is preserved as `apple-ranges-unreserved.json`; adding the same resource
preparation as the existing product fixed the diagnostic harness. A sandboxed
CLI attempt reported unavailable locale; the authorized native run succeeded.
No microphone, private recordings, cloud ASR or second production ASR was used.
