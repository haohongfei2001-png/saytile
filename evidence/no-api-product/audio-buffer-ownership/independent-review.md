# Independent converter ownership read-review

Reviewed the production AudioCapture diff and new CaptureConverterTests after the confirmed no-api.2 intermediate gap. No source edits or additional tests were performed by this reviewer.

The minimal correction retains the same newly read input buffer until AVAudioConverter actually requests it through its input callback. Previously, a call could fill the output solely from earlier input and return without invoking that callback; the new ring batch was then discarded. The red receipt reports 22,050 Hz output shrinking from 44,125 to 41,153 frames, with whole-waveform inequality, under the variable ring-batch pattern.

Read-review findings:

- The supplied flag and source buffer remain the same across repeat calls. Once supplied, that batch is not supplied again. Output remains ordered; each returned Data enters acceptPCM exactly once.
- The shared path remains converter → segmenter → append. append writes the same Data to PCMJournal before speech.append. There is no separate conversion, padding, sample insertion, prime-method change or converter reset that could hide a gap or diverge raw audio from ASR.
- EOS still drains the converter before segmenter.finish and endUtterance. The extracted drain routine retains the former stop conditions. The new regression requires a second drain to be empty.
- The helper runs synchronously within CaptureWorker. It adds no unowned Task or await/reentrancy inside conversion. stop still waits for runTask before final drain. The result array holds this bounded ring batch plus the converter's pending output, not a session-duration audio history.
- The no-progress branch fails visibly instead of silently retiring an unconsumed input batch.

No additional confirmed P0/P1 was found in this correction. **Code review passes; runtime acceptance remains conditional on actual green regression and the new frozen long-run evidence.** At review time native-green.log still contained a build-system Testing-module failure, not a passing runtime receipt; the owning agent is resolving that build invocation. The four-rate test compares beginning/middle/end waveform byte-for-byte to contiguous conversion without padding, but does not alone establish 30-minute real-time behavior or hardware/microphone reliability.
