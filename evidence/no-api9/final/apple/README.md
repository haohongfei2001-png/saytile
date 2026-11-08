# no-api.9 local speech corpus

The probe linked the production SaytileKit library built from `dc26fe3c59ba55994d29e99ada8d2f0b49ad9886`, tree `f138f6733a642a2e53da22b3647aaf5744cb308b`. Two synthetic Mandarin voices produced eight new clips lasting 48.7029375 seconds. All eight yielded progressive candidates and a completed, dispatchable revision in the isolated store.

| Measurement | Result |
| --- | --- |
| Progressive candidates per utterance | 21–31 |
| First text min / median / max | 1.181 / 1.218 / 1.230 s |
| Finalization after input min / median / max | 0.031 / 0.059 / 0.099 s |
| Normalized CER per utterance | 0–26.32% |
| Expected phrases absent from the transcripts | “Mac”, “保存原音”, “充电器”, “修改开始时间” |

The probe normalizes case and character width and removes punctuation and whitespace before calculating CER. `apple-corpus.json` retains the expected strings, actual transcripts and timing events. This sample covers local synthetic speech. Human-speech accuracy, comparative cloud-model gain and real-provider delay remain unmeasured.

The current probe's initial inventory reported Chinese supported and uninstalled with zero reservations out of five. One bounded official product preparation returned with the Chinese locale installed and reserved. It released no other locale. Downloaded bytes were unmeasured. No microphone or provider account was used. `fixture-identity.json`, `asset-preparation.json`, `probe-source-identity.json`, `receipt.json` and `apple-summary.json` preserve provenance and individual output hashes. The signed package's own synthetic check has a separate receipt.
