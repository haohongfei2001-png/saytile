# Release Apple Speech corpus

Eight new synthetic Mandarin clips using two voices totaled 48.7029375 seconds. The current Apple Speech implementation produced progressive candidates and a completed, dispatchable revision for every clip in its isolated store. The probe linked the SaytileKit library built from `69b90939fd688b35448f976950e96db0ce5b602a`, tree `06f1ac6982591bce64c98bd93e26eb0ccba0cfd8`.

| Measurement | Result |
| --- | --- |
| Progressive candidates per utterance | 21–31 |
| First text min / median / max | 1.123 / 1.147 / 1.168 s |
| Finalization after input min / median / max | 0.030 / 0.048 / 0.129 s |
| Normalized CER per utterance | 0–26.32% |
| Expected phrases missing from transcripts | “Mac”, “保存原音”, “充电器”, “修改开始时间” |

The CER calculation folds width and case and removes punctuation and whitespace. `apple-corpus.json` records expected strings, transcripts, timings and per-utterance errors. Results apply to these synthetic recordings. Human-speech accuracy, provider fusion gain and additional cloud confirmation latency remain unmeasured.

The freshly compiled corpus executable initially reported Chinese supported and uninstalled with zero reservations out of five. One bounded official product preparation returned with Chinese installed and reserved. No other locale was released. Download size was unmeasured. The run did not open the microphone or call a cloud speech provider. `asset-preparation.json`, `fixture-identity.json`, `probe-source-identity.json`, `receipt.json` and `apple-summary.json` bind the raw results to their source, inputs and executable. The separate extracted-app check has its own receipt.
