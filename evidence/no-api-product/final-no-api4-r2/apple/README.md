# Frozen 1067f1ad local Apple synthetic corpus

Eight prerecorded synthetic cases totaling 48.7029375 seconds completed through installed Apple Speech, producing local candidates, unified evidence and dispatchable revisions. No microphone, cloud service, asset preparation request, or private recording was used. The manifest, eight generated AIFF files and executed probe hashes are recorded in `receipt.json`; the probe hash was identical before/after. The shared source identities are in `../input`.

Normalized CER was 0–0.2631579. Four cases still missed critical phrases (Mac, 保存原音, 充电器, 修改开始时间); `apple-corpus.json` retains each expected/recognized result. This is an engineering integration result, **not** a claim that all eight transcriptions were accurate or that real human speech/cloud quality has been validated.

First-text latency: 1.1343–1.1809 seconds, median 1.1486. Completion after input ended: 0.0319–0.0892 seconds, median 0.0432. These measurements apply to this synthetic local fixture run only.
