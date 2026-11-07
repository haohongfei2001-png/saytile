# Live-paced VAD, saved audio and real local Apple recognition

One isolated process linked the tested SaytileKit library from `dc26fe3c59ba55994d29e99ada8d2f0b49ad9886`, tree `f138f6733a642a2e53da22b3647aaf5744cb308b`. It fed the existing `daily` and `tail` synthetic Mandarin AIFFs into the production audio ring on 20 ms wall-clock deadlines. The single `CaptureWorker` used its default recognition factory. WebRTC VAD opened two journals. Each utterance's PCM was written to its own WAV and offered to the real local Apple recognition session. Apple candidates and the chosen visible revisions were observed through the same Store while capture continued. [Source/fixture/binary identities](identity.json) · [Probe](LocalVADAppleProbe.swift) · [Raw observations and candidates](raw-report.json)

The source was 22,050 Hz mono. Feed duration was 13.924 s for 307,212 source frames: 0.25 s initial silence, first AIFF, 1.6 s inserted silence, second AIFF and 1.6 s trailing silence. The Apple Chinese resource initially reported supported but not installed. The ordinary product resource-preparation operation was called once, after which the system reported the locale installed. This was a language-resource operation. No microphone or speaker was opened, no TCC prompt or service credential was needed, and default cloud recognition was disabled.

| Observation | First utterance, daily | Second utterance, tail |
|---|---:|---:|
| First VAD active transition, from feed start | 0.347 s | 6.965 s |
| First nonempty selected archive text, while recording | 1.201 s | 8.110 s |
| Changed nonempty texts observed while the row was open | 6 | 8 |
| Durable Apple candidates | 25 | 25 |
| VAD returned to standby | 6.020 s | 13.082 s |
| Completed archive row observed | 6.201 s | 13.202 s |
| Saved WAV, mono int16 at 16 kHz | 95,680 frames | 113,280 frames |
| Final selected text | 今天下午 3:00开会 ，请提前 10分钟到达会议室 | 即使识别失败也要继续收音 ，原始录音必须完整保留 |

The WAVs passed independent Python RIFF/header/frame checks. The final revisions and Apple candidates belonged to their respective recording IDs. SQLite integrity was OK, the ring reported zero drops, the worker reported zero capture errors, and the recording-specific upload-grant table was empty. All 18 assertions passed. The first visible archive updates were observed about 0.854 s and 1.145 s after their respective VAD onsets. Completion was observed about 0.181 s and 0.120 s after each VAD end. These times are sampled Store observations on one Mac. [Summary with WAV SHA-256 values](summary.json) · [Process output](run.log)

The worker was stopped, its remaining recognition work drained, and its independent Store closed. The child exited 0 in 15.687 s. The source revision, tested library, probe executable and synthetic inputs retained their hashes. The original fixture recipe uses the macOS `say` voices/rates in the tracked Mandarin corpus. Only input fingerprints and saved-WAV fingerprints are published here. Neither the existing AIFF files nor generated WAV bytes are duplicated in this evidence directory. [Corpus and generation parameters](../../../../tests/fixtures/MandarinCorpus.json) · [Fixture generation recipe](../../../../scripts/test-audio-corpus.sh) · [Original eight-case fixture receipt](../apple/receipt.json)

## Reproduction boundary

The [runner](run.py) checks the exact checkout, the recorded AIFF hashes and the current full-suite library receipt before compiling the probe with test visibility. It makes a new temporary Store and refuses to overwrite an existing run log. To reproduce in a separate test checkout, use the same-version generated corpus and native library, placing their actual paths in that checkout's fresh Apple/native test receipts. Copy only the runner and probe into an empty sibling directory of `local-vad-apple` under `evidence/no-api9/final/` and run that copy of `run.py`. The original build command, executable arguments and file hashes are preserved in this run's identity. The recording-classification assertions were set before this single execution.

This closes the live-paced synthetic ring → VAD → independent saved PCM → actual Apple partial and final path. It did not exercise the microphone/AVAudioEngine hardware tap, real human speech, external insertion, a live cloud provider or ASR-enabled hours of continuous operation. VAD deliberately excludes some silence. The saved WAV durations are not a claim that every supplied silence sample is archived.
