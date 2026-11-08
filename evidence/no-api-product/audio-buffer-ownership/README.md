# Confirmed mid-stream capture loss: converter input ownership

The earlier `d4b9dbe` 30-minute run is **not accepted as lossless capture**. Its ring-overflow count, file availability, WAV payload lengths, SQLite totals and process lifetime checks all passed, but those checks did not compare persisted audio with the input waveform. The 1,486-frame / 92.875 ms shortfall was a real mid-stream gap. Original evidence is preserved in `../intermediate-d4b9dbe/`; the previous successful assessment is a historical, narrower observation, not a release verdict.

## What established the cause

Only the known root-generated Tingting synthetic AIFF was used: SHA256 `d7deb6ef7c7a6cc330fbb4ee82eb2733f82ee7761634e6df55f650037bf0b751`, 125,714 bytes, 60,809 mono source frames at 22,050 Hz. The retained small source asset is `../intermediate-d4b9dbe/local/realtime-synthetic-source.aiff`. No microphone, user recording, permission change or cloud API was involved.

1. The unmodified production `CaptureWorker.run → stop → flushTail` processed the complete 2.757778-second source into **44,125 frames**, matching rate conversion. Independent actual AVAudioConverter runs using fixed 1,024-, 8,192- and whole-file batches also produced 44,125 frames with normal priming. Thus simple start/end conversion did not reproduce the gap (`first-probe.log`).
2. A converter-only, accelerated 1,800-second reference supplied all **39,690,000 source frames** and produced **28,800,000 output frames**, including 1,494 EOS-drained frames. It excluded VAD and wall-clock claims (`long-converter.log`). The original captured waveform matched the reference at the beginning and midpoint. Its first differing sample was at **918.80375 seconds**; the last-second windows best matched the reference **1,486 frames later**, with only 0.094/0.214 Int16 RMS rounding differences in the inspected windows. This established a middle gap rather than pure initial/final silence trimming or a valid time-base difference (`waveform-window-comparison.json`, `tail-waveform-correlation.json`).
3. The short source with repeating input batch sizes **[8192, 1024, 1024, 512, 1024]** reproduced the defect. With unchanged normal priming, output fell to **41,153 frames**. Four converter calls returned **776 output frames from internal older input without invoking the input callback**. Each call therefore left `supplied=false` while the old worker retired its newly read 1,024-frame batch. The ring's dropped count cannot detect this downstream loss. Other priming modes reproduced the same missing-batch mechanism (`mixed-probe.log`).

The original gap occurred near a single diagnostic vmmap observation, but time proximity does not establish causation. The short batch-pattern reproduction does not use vmmap, sleep, user interaction or the scheduler to reproduce the ownership defect.

## Minimal production correction

`CaptureWorker.convertCapturedSamples` retains the current ring batch and continues consuming converter output **until its input callback actually accepts that batch**. A no-input/no-output iteration throws a capture failure instead of spinning. The source buffer is not retired merely because `convert` returned output. There is no zero padding, invented sample, larger ring, priming change or replacement resampling algorithm.

The existing conversion and EOS logic were extracted into methods called by both the actual worker and the regression. Converted output still enters `acceptPCM` in order, and journal/recognition still receive the same resulting PCM. EOS draining is unchanged in behavior and is verified not to replay output when called again. The temporary output arrays are bounded by converter buffering, not total recording duration.

The macOS SDK's `AVAudioConverter.h` explicitly allows the input callback to supply more or fewer packets than requested. Returning the complete source buffer is therefore not itself a protocol violation. The defect was discarding a batch that the callback had **never requested or received**. Relevant SDK definitions are `AVAudioConverterInputBlock` and `convertToBuffer:error:withInputFromBlock:`. The inspected primary source is the installed `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/AVFAudio.framework/Headers/AVAudioConverter.h`, especially lines 127–152.

## Persistent red → green

`CaptureConverterTests.varyingRingBatchSizesPreserveCompleteWaveform` uses deterministic non-silent synthetic input with distinct first/last transients at 16,000, 22,050, 44,100 and 48,000 Hz. An independent contiguous AVAudioConverter reference is compared against the production worker conversion methods. The assertion checks **every PCM byte**, not only duration, and checks that a second EOS drain is empty.

- **Red:** the old single-convert behavior was extracted without fixing it (`red-extraction.patch`, `red-source-identity.json`). The 22,050-Hz case produced **41,153 instead of 44,125 frames** and failed both frame-count and complete-waveform checks. The other three rates passed. `native-red.log` retains the two failing assertions.
- **Green:** after retaining the unaccepted input batch, all four rates matched the complete reference waveform exactly. The 22,050-Hz output is **44,125 / 44,125 frames**. The focused run passed **14 tests in 5 suites**, including audio journal/ring/VAD, storage faults, capture task ownership and capture-to-recognition integration (`native-green.log`).
- Two intermediate build attempts failed before tests: the default direct Swift invocation omitted the explicit Testing macro plugin, and forcing native SwiftPM omitted CLT 6.4 Testing.framework discovery. Their logs remain separately named. The successful run uses the repository's existing CLT-aware wrapper; these tooling failures are not reported as test success or production defects.

Reproduce the meaningful regression using the maintained wrapper:

```sh
SAYTILE_TEST_SCRATCH=/tmp/saytile-converter-regression \
SAYTILE_TEST_LOG=/tmp/saytile-converter-regression.log \
  scripts/test-native.sh --filter 'CaptureConverterTests|AudioTests|AudioStorageFailureTests|CaptureOwnershipTests|CaptureCloudIntegrationTests'
```

The isolated `ConverterBoundaryProbe.swift` source is retained here for the original batch/callback diagnosis. Compile it against a complete SaytileKit static build with `-enable-testing`, the build's CAudio module map and `-lc++`, following `scripts/test-rc-storage-processes.py`'s existing linkage. Run with `[syntheticAIFF, newDisposableOutputDirectory]` for the short fixed/mixed/priming cases; add `1800` for the accelerated fixed-batch reference. This reference is **not** a second wall-clock soak. Raw repeated PCM stays in disposable `/tmp` output, not the repository.

A new frozen-runtime full verification and 30-minute run remain required. The new final assessment must compare the persisted continuous synthetic waveform against an independently converted reference, including beginning, middle and end; ring-drop and internal WAV/SQLite agreement alone are insufficient.
