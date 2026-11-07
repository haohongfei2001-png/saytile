# no-api.7 on-device Apple Speech

The current test executable linked the SaytileKit static library from the fresh full build of `4b97bd89b258fea29a0be61d4bd4c23cb5ab428c`, tree `4aac670d6edfcce0c12ed22fa3cd5c68e66061b9`. The eight synthesized Mandarin fixtures total 48.702938 seconds. Each record completed through Apple Speech, produced progressive candidates, reached a dispatchable UTF-16 revision and saved local evidence in the isolated store. No microphone, personal audio or cloud-provider account was used.

The first in-process inventory query reported Chinese supported and uninstalled, with zero reservations out of 5. One bounded call to the production `AppleSpeechService.prepare()` returned with Chinese installed and reserved. The inventory queries were 0.052 seconds apart. No locale was released. Bytes transferred were unmeasured.

| Measure | Result |
| --- | --- |
| Completed utterances | 8/8 |
| First text min / median / max | 1.143 / 1.199 / 1.221 s |
| Finalization after input min / median / max | 0.038 / 0.051 / 0.130 s |
| Per-utterance normalized CER range | 0.00% to 26.32% |
| Progressive candidates per utterance | 21 to 31 |

The CER calculation in `AudioCorpusProbe.swift` folds width and case and removes whitespace and punctuation. The expected phrases missing from the outputs were mixed — Mac, pauses — 保存原音, second_voice — 充电器, correction — 修改开始时间. The full transcripts, expected strings, timings and per-utterance errors are preserved in `apple-corpus.json`. The corpus covers two synthetic voices. Generalization to human speech and comparative gains from provider fusion remain unmeasured.

`receipt.json`, `asset-preparation.json`, `probe-source-identity.json` and `fixture-identity.json` record the isolated directories, input and executable hashes and the official resource preparation boundary. The only change to the tracked corpus probe was its optional preparation call, which recorded inventory before and after and bounded the official operation. The normalization, recognition and store checks used the current tracked implementation.
