# RC1 production audio and recognition audit

Audited source: `fdaaac4ae15bdbf11c3b2784441ec052828fa49a` (research branch HEAD at inspection). This is a source audit, not a claim that human-speech boundary cases have already passed on a Mac. No production source is changed.

## Findings that affect the integration decision

| Area | Verified behavior | Consequence |
|---|---|---|
| Language | `SpeechRecognition.swift` resolves `zh-CN` for both asset preparation and `LiveSpeechSession`; `.progressiveTranscription` is used. | The current default is a fixed Chinese recognizer. An English locale oracle experiment is useful for diagnosis but does not represent the shipping policy. |
| Front-end | `AudioCapture.swift` converts mono Float32 capture to 16 kHz mono Int16. `CAudio/VAD.c` uses WebRTC **mode 2**, 16 kHz. `VoiceSegmenter` consumes 320 samples / 640 bytes / 20 ms. | A direct WAV-to-SpeechAnalyzer experiment does not exercise the production WebRTC gate. Apple's `SpeechDetector` is an additional downstream module, not this gate. |
| Start | Up to 50 frames (1 second) of pre-roll; `speechVotes` increases by one on voiced frames and decreases by one on unvoiced frames; threshold is 3. | This is a leaky vote, not a strict requirement for three consecutive voiced frames. Short/quiet speech may never trigger. Pre-roll preserves preceding sound only within its 1-second window. |
| End | 40 consecutive unvoiced frames are appended before `.end`. | Endpointing itself adds approximately 800 ms after the last frame classified as speech, before recognizer finalization. Do not attribute all final latency to the model. |
| Long speech | `.end` after 1,500 **post-begin** active frames, followed by a new recording and a new `LiveSpeechSession` when VAD triggers again. | The unit can contain up to approximately 31 seconds including pre-roll. Recognition context resets in the middle of a sentence. Disk chunk rotation is separate. |
| Disk | `PCMJournal` checkpoints about once per second and rotates WAV chunks at 15 seconds. | The 15-second file boundary does not itself restart ASR. The 30-second VAD boundary does. |
| Draining sessions | On each utterance end, complete sessions are removed, the just-ended session is appended to `retired`, and all but the newest two are cancelled if more than two remain. | Under slow finalization or rapid short utterances, the oldest unfinished result can be cancelled. Saved audio is retained; completion of its transcript is not guaranteed. |
| Backpressure | `LiveSpeechSession` uses `.bufferingOldest(300)` and fails/cancels when a PCM yield is dropped. A second 300-element queue holds analyzer inputs. | This is bounded behavior, not unbounded RAM use. For normal 20-ms PCM events the first queue holds roughly 6 seconds. Running a file faster than real time can deliberately hit a limit and cannot be reported as live latency. |
| Final timeout | `LiveSpeechSession.finish()` installs a 20-second cancellation watchdog. | This is an upper bound on waiting, not evidence for a 20-second normal finalization time. Failure/retry evidence must distinguish this from provider accuracy. |
| Store attempt | Each recording has a single `active_attempt`; `beginRecognition` overwrites it, and `validTicket` checks the recording ID, audio epoch, attempt ID and running state. | Starting two independent recognizers against the same recording with two tickets invalidates the first. A naive parallel realtime/final engine integration is incorrect. |

## Does the 30-second rotation lose PCM?

There is **no deterministic dropped frame or duplicate frame at an ordinary continuous-speech rotation in this implementation**. The boundary frame is appended to the old unit before `.end`. Subsequent frames enter the next pre-roll; when speech votes reach the threshold, that pre-roll is appended once to the new unit. The source does not deliberately overlap audio between consecutive ASR units.

The guarantee is conditional: the next unit must trigger. If recording stops before the new unit triggers, or speech never crosses the gate again, inactive pre-roll is discarded. If delayed triggering exceeds the pre-roll window, earlier inactive frames are evicted. These are VAD admission/stop-boundary risks, not proof of an unconditional 30-second slicing gap. A new recognizer also loses linguistic context even when the PCM is complete. These different failure classes must be reported separately.

## Stop and tail handling

`CaptureWorker.stop()` sets `stopping`, awaits the running capture loop, drains `AVAudioConverter` with `.endOfStream`, then invokes `VoiceSegmenter.finish()` and closes the utterance. The running loop continues reading the ring until empty when stopping. A claim that RC1 simply forgets to flush the resampler or all sub-frame tail audio would be false.

If a VAD unit is active, `finish()` emits any pending complete Int16 samples, including a tail shorter than 20 ms, then `.end`. An unmatched odd byte is not a complete PCM sample. If no unit is active, `finish()` returns no events and discards pre-roll/pending audio. Therefore “original audio is saved independently of ASR” means **admitted VAD units**, not a continuous archive of every microphone sample. Existing `AudioLifecycleTests` verify active sub-frame tail handling and silent standby using generated signals; they do not measure quiet human negatives, brief numbers, or a stop immediately after forced rotation.

## Resampling and channels

The capture ring averages channels arithmetically before the AVAudioConverter stage. This is deterministic downmixing; anti-phase stereo could cancel, but no such failure was measured here. Capture conversion uses actual device sample rate, not an assumed 16 kHz clock. Both the capture converter and the later Apple-format converter contain end-of-stream draining. A replay beginning at canonical 16 kHz PCM can assess downstream production segmentation/recognition but cannot certify the microphone tap, channel downmix, ring scheduling, or device-rate converter.

## Required coordination for any replacement engine

Keep one owner of a recording's recognition ticket and revision publication. Engine adapters produce candidate events to that owner. If a separate finalizer is later justified, either serialize attempts after the realtime attempt has drained or explicitly introduce persisted per-engine attempts with a single selected publisher. Do not simply call `beginRecognition` twice and hope both streams will be retained.

Preserve the existing audio epoch and attempt guards, immutable final versions, explicit user-edit preference, stable UTF-16 prefix dispatch, target binding invalidation and reservation/confirmation semantics. A higher-accuracy final revision can be retained as another version. It must not automatically rewrite text already delivered to an external input target or resend the full transcript.

For a cloud realtime integration, separate durable audio chunk boundaries from recognizer context boundaries. The existing 15-second journal chunks need not end a provider session. Prefer explicit provider finalization and a bounded durable retry queue to cancelling an arbitrary old finalizer solely because two newer units have ended. A persistent longer stream still requires documented reconnection, offset and duplicate-suppression handling; it does not permit dropping the independent local journal.

### Minimal single-engine cloud policy

The smallest proposed cloud change keeps **one logical recording, one ticket and one provider connection** for a continuous utterance. Disable the 30-second forced VAD/recording rotation for the cloud policy, retain 15-second journal file rotation, and use a 2.0-second local silence threshold only to release recording/connection resources. The 2.0-second setting is an engineering starting value, not an experimentally selected optimum or a wait imposed on stable text. Provider-confirmed stable text may be published before local closure. Keep Apple's current boundary policy separate. This is an implementation recommendation, not a claim that a Soniox production integration has been tested.

At local closure, close and register the journal, request provider input completion, and let the recognizer drain in its own task. The capture loop must not await the entire provider finalization. A new utterance can create a new recording/ticket while the old one drains; different recordings' tickets do not invalidate one another. Do not call `finishRecognition` for the old ticket until its result stream has actually drained. Apply explicit timeout/connection-budget behavior; when recognition admission is unavailable, preserve the new local recording for retry rather than cancelling an arbitrary admitted finalizer.

Two existing input-protection constraints still apply. First, `createBinding` records the latest recording rowid and excludes older recordings from a new binding. Rebinding during a long recording therefore needs a new logical recording boundary; simply removing the 30-second threshold would otherwise leave subsequent speech ineligible for that binding. Second, if a newer recording is already dispatched, a late final from an older recording is deliberately deferred by `lateRecognitionDeferred`; retain that guard and retain the text for manual use. These guards must not be weakened to make the new provider appear seamless. Provider session limits, reconnects and failures also need explicit logical boundaries and recovery, not an assertion of unlimited continuous operation.

## Small, targeted checks only

Use existing legal corpus files or clearly labelled derivatives; no additional large corpus is required.

1. One continuous voiced span that crosses a forced rotation, including a number/negation near the boundary. Compare input PCM with concatenated journal PCM and inspect transcript units. A repeated/concatenated fixture can test control flow but must not be scored as natural-speech accuracy.
2. Stop during an active VAD frame and immediately after a forced rotation but before the next trigger. Record admitted bytes and the resulting number of recordings separately from ASR text.
3. One short negative/number and one existing mixed-language failure. Compare direct replay with the complete downstream path.
4. For coordination, begin two tickets for one isolated recording and confirm the older ticket is rejected. This is a store contract check, not a model benchmark. Simulated slow finalization may demonstrate the `retired` cancellation rule, but must not be described as measured Apple/cloud behavior.

The small research replay companion executes the unchanged production `VoiceSegmenter` compiled with its production WebRTC C code. It exports the exact admitted PCM and source intervals, records SHA-256 hashes, distinguishes the 30-second forced boundary from a VAD silence boundary, and checks that each segment equals its recorded input range. It **does not execute** `CaptureWorker`, `LiveSpeechSession`, journal durability, microphone capture, resampling, or external text dispatch; it is not an end-to-end recognition benchmark or a latency measurement. The exported WAV header comes from production `PCMJournal.header`, but file writing is only research export.

Run on macOS 26 with Swift 6, using a canonical 16 kHz mono PCM16 WAV and a new output directory outside the repository:

```sh
bash research/asr/benchmark/run_production_vad_probe.sh /absolute/existing.wav /absolute/new-output/original
bash research/asr/benchmark/run_production_vad_probe.sh /absolute/existing.wav /absolute/new-output/repeated --repeat 12
bash research/asr/benchmark/run_production_vad_probe.sh /absolute/existing.wav /absolute/new-output/tail --active-tail
```

Choose the repeat count to exceed 60 seconds. Repetition is a labelled control-flow derivative, not a new human accuracy sample. A repeated clip containing pauses of 800 ms or longer may repeatedly end on silence without ever reaching the forced boundary; verify `forced_rotations` in the report before claiming that boundary was tested. `--active-tail` stops at the first observed trigger plus up to 43 samples; verify `active_tail_trigger_observed`, `speaking_at_finish`, and `finish_audio_bytes` (86 when enough input remains). Omitted samples include intended standby silence and unadmitted audio; they are not automatically speech loss. No recognizer accuracy or finalization result is inferred from these probes.

## Evidence locations

- `Sources/CAudio/VAD.c`: mode and sample rate.
- `Sources/CAudio/AudioRing.c`: channel handling and overflow counters.
- `Sources/SaytileKit/AudioJournal.swift`: `VoiceSegmenter`, pre-roll, forced rotation, EOF; `PCMJournal` durability and file rotation.
- `Sources/SaytileKit/AudioCapture.swift`: `CaptureWorker.acceptPCM`, `flushTail`, `endUtterance`, bounded retired recognizers.
- `Sources/SaytileKit/SpeechRecognition.swift`: locale, bounded queues, timeout, Apple input conversion, revision updates.
- `Sources/SaytileKit/Store.swift`: `beginRecognition`, `validTicket`, `applyRecognition`, `finishRecognition`.
- `tests/SaytileKitTests/AudioLifecycleTests.swift`: existing synthetic EOF assertions.
- `research/asr-2026-11-06/scripts/AppleReplay.swift`: direct whole-file/paced baseline; it shares result accumulation but bypasses production WebRTC/CaptureWorker.

### Validation status

The probe compiled and all three targeted cases ran on the authorized Mac, verified at **2026-11-06 11:44 UTC**, macOS **27.0**, arm64, Apple Swift **6.4**. The shell script also passes `bash -n`. Only research files were copied; production source remained unchanged. An initial shell setup failed because the remote shell inherited a removed working directory; explicitly changing to the repository resolved that setup failure before successful probe execution.

| Case | Actually fed | Result |
|---|---|---|
| Existing `ascend-01047.wav` | 126,400 samples / 7.9 seconds | One unit; every sample matched its input range; zero omitted and zero overlapping samples. |
| Same PCM repeated 10 times | 1,264,000 samples / 79 seconds | **Two forced rotations**; units of 480,960, 480,960 and 302,080 samples (30.06, 30.06, 18.88 seconds); all exact input matches; zero omitted and zero overlapping samples. |
| Active partial-frame tail | 1,003 samples / 0.0626875 seconds | Active at finish; `finish()` emitted **86 bytes / 43 samples**; output matched all fed samples, with no omission or overlap. |

The source WAV SHA-256 is `a39c0a82c2d9582f8c59d1b3a31b3e8d7a49f5c6daa01b0fbfd3db616b102205`; its existing manifest declares ASCEND, CC-BY-SA-4.0, source revision `737e9800ae31be9932ba8464c80366559bd28424`. Repetition and truncation are labelled control-flow derivatives; they are not natural-speech accuracy samples.

Text evidence is in `research/asr/results/vad-probes/`: per-case `report.json`, source HEAD and source SHA-256 files, plus fixture/environment metadata. Raw input, exported WAVs and build logs remain outside the repository at `/Users/hhf/.codex/saytile-asr-research-20261106/vad-probes/` (original input remains in the adjacent `audio/` directory). Each run records the checkout HEAD and SHA-256 of the Swift segmenter/journal source, the C VAD wrapper, and the harness; these hashes do not replace recording the repository revision for the vendored WebRTC implementation.

These results validate the expected forced-boundary continuity and active-tail behavior for these inputs. They do **not** measure ASR, microphone capture, resampling, cloud latency, natural long-speech recognition, inactive tail after rotation, or quiet-word recall. No additional corpus or larger matrix was run.
