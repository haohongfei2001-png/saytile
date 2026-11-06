# Three production VoiceSegmenter probes

Verified on the authorized Mac on 2026-11-06. This directory contains **text only**. The raw audio, exported WAVs and build logs are outside the repository; locations and runtime versions are in `environment.json` and `fixture.json`.

The executable compiled the unchanged production `AudioJournal.swift` and production `CAudio` with a research harness. It runs the real WebRTC mode-2 detector and `VoiceSegmenter`. It does not run `CaptureWorker`, Apple/cloud recognition, microphone capture, input resampling, journal durability or target text dispatch.

| Case | Input samples | Segments | Forced rotations | Omitted / overlapping samples | Extra observation |
|---|---:|---:|---:|---:|---|
| original | 126400 | 1 | 0 | 0 / 0 | Existing 7.9-second ASCEND clip, unchanged. |
| repeated | 1264000 | 3 | 2 | 0 / 0 | Same PCM repeated 10 times; segment lengths 30.06, 30.06, 18.88 seconds. |
| tail | 1003 | 1 | 0 | 0 / 0 | Active EOF flushed the pending 43 samples (86 bytes). |

Every segment's `exact_input_range_match` is true. Repetition/truncation are labelled control-flow derivatives, not accuracy data. Zero omitted samples in these cases does not imply that the VAD can never reject quiet speech or discard an inactive pending tail.

Each case contains its raw JSON report plus checkout HEAD and source hashes. `fixture.json` retains the pre-existing source/licence manifest record, input hash and transformations. The source audio licence is CC-BY-SA-4.0; no audio is redistributed here.

Reproduce from the repository root with the existing canonical PCM16 mono 16 kHz file and new output directories:

```sh
bash research/asr/benchmark/run_production_vad_probe.sh /absolute/ascend-01047.wav /absolute/probe-original
bash research/asr/benchmark/run_production_vad_probe.sh /absolute/ascend-01047.wav /absolute/probe-repeated --repeat 10
bash research/asr/benchmark/run_production_vad_probe.sh /absolute/ascend-01047.wav /absolute/probe-tail --active-tail
```

The production code audit and the limits of these observations are documented in `research/asr/PRODUCTION_AUDIT.md`. The proposed cloud boundary policy has not been exercised by these probes.
