# Lifecycle and saved-audio replay review

Base: `45af67049ddee2553fe1929a812aecb83cc157e4`, with this review's working changes. This is a no-key engineering review, not microphone, TCC-prompt, physical sleep/wake, device hot-unplug, cloud-provider or final-package acceptance. No permission, device, foreground app, user database, real recording or credentials were changed/read.

## Reproduced and fixed

1. **First microphone permission prompt cancelled by the polling timer.** `CaptureState.starting` counts as running. The old one-second lifecycle poll treated `.notDetermined` as revoked and cleared the user's pending start while the first system prompt remained unanswered. The production permission decision now exempts only `.starting + .notDetermined`; denied/restricted starts and permission reset during listening/speaking still require suspension. After the permission await, start also refreshes the independent session/lock gate before constructing the engine. The permission status inputs are synthetic; no system prompt was displayed. The old predicate was extracted unchanged before running the red test.

2. **Saved audio was fed at 2× while a healthy optional Meta stream consumes at 1×.** The retry loop sent 6,400 PCM bytes (200 ms of mono Int16/16 kHz audio) every 100 ms. The existing 300-block provider queue could overflow on an ordinary five-minute recovery. The production loop is now `SavedAudioReplay.feed`, with the actual block duration controlling the wait, including a short final block. This deliberately replays saved audio at approximately real time for all recognition sessions; it does not change live capture and does not enlarge any queue. Real temporary files plus an injected wait closure exercise the same production reader and count a virtual 1× consumer: the old five-minute feed accumulated 4,803,200 bytes, versus at most one 6,400-byte block after the fix. This is a deterministic timing/queue-bound model, **not a real Meta call**. Cancellation interrupts before another block is offered.

3. **Tap callback assumed the old channel layout and sample clock.** An injected 1→2-channel buffer was previously accepted using the installation-time channel count. The inverse change could index beyond the new channel-pointer array. Same-channel 16→48 kHz data was also accepted for the old converter, misrepresenting its duration. Before entering the C ring writer, the callback now requires matching channel count and sample rate, and noninterleaved Float32 PCM. An incompatible block records a gap through the existing zero-channel failure path; it is never silently dropped or read using stale pointers/clock. The worker already seals prior durable audio on a gap, and its message now accurately describes discontinuous input. Both 1→2 and 2→1 injected layouts and a 16→48 kHz change are tested. This verifies the callback boundary; it does not claim that a physical audio-device transition emitted such a buffer on this Mac.

## Verification

- `lifecycle-red.log`: 8 tests / 2 suites; the pending-start test and both replay timing tests fail against the original decisions. Full failure evidence retained.
- `lifecycle-tap-red.log`: the first two fixes pass; the newly added channel-layout test fails because 320 wrong-layout frames entered the ring.
- `lifecycle-green.log`: the first **20 tests / 8 suites PASS**, before the independent sample-rate follow-up.
- `lifecycle-rate-red.log`: same-channel 16→48 kHz test fails because 320 wrong-rate frames enter the ring without a discontinuity marker.
- `lifecycle-final-green.log`: **21 tests / 8 suites PASS**, including 6 newly added test functions; the channel-layout test has two cases. This targeted count also includes existing capture tails, storage-fault handling, lock/session gates, shutdown, cloud transport fixtures and ownership regressions; it is not additive to the full suite count.
- Existing lock/session tests cover independent sleep/session/lock reasons, a missing WindowServer snapshot, an untrusted unlock hint, and the local notification bridge. Existing controller tests cover shutdown and ownership during an awaited stop. These were rerun as regressions, not reported as newly fixed defects.
- `git diff --check`: PASS at review time.

Command:

```sh
SAYTILE_TEST_SCRATCH=/tmp/saytile-no-key-lifecycle-tests \
SAYTILE_TEST_LOG=research/asr/validation/rc2-no-key/lifecycle-final-green.log \
scripts/test-native.sh --filter 'SavedAudioReplayTests|AudioLifecycleGateTests|AudioTapTests|AudioLifecycleTests|AudioShutdownTests|CaptureOwnershipTests|AudioStorageFailureTests|CaptureCloudIntegrationTests'
```

## Wall-clock synthetic resource check

The existing `scripts/test-audio-realtime.sh` is reused unchanged. An initial build stopped because another agent modified `MultiRecognitionSession.swift` during compilation; **no resource run occurred** on that attempt. Its output is retained as `lifecycle-realtime-build-race.log`. The follow-up uses an isolated copy of the working source, identified in `lifecycle-realtime-source-manifest.json`, to avoid that build race. The copy predates the additional sample-rate guard (the fixture's rate is constant); it is not the final source or RC2 package.

The owned fixture repeats 2 seconds of synthetic 120 Hz + 660 Hz harmonics and 1 second of silence, mono 16 kHz Int16. It is generated with Python's `wave`/`struct`/`math` modules, then converted with `/usr/bin/afconvert -f AIFF -d BEI16`; no synthesis service, microphone or speaker is used. WAV SHA256 `3e82e3c45e8407f2b1a6964c7005271106520f7827cf8edf06057688ad333d45`; AIFF SHA256 `3aa84cf739898fe9aef10c5743f0c9d0a3f873cd5b387ac5a1030e64527d2445`.

Follow-up command: `SAYTILE_AUDIO_SCRATCH=/tmp/saytile-no-key-realtime-snapshot-build /tmp/saytile-no-key-realtime-snapshot/scripts/test-audio-realtime.sh /tmp/saytile-no-key-lifecycle-synthetic.aiff 120`. The script feeds the actual C ring → AVAudioConverter → VAD → journal → SQLite worker at wall-clock speed with ASR disabled. Results are recorded in `lifecycle-realtime.log`; this short run cannot establish 24/72-hour stability, hardware-clock behavior or whole-machine energy use.

**Completed, exit 0:** 120 seconds fed, 1,920,000 source frames, 0 ring dropped frames; 40 records, all available and finished; 119.92 seconds saved, 3,839,200 audio bytes; 40 pending ASR records as expected with recognition disabled. VAD-selected saved duration is reported separately from source duration and is not claimed to be byte-identical preservation of the whole fixture. `/usr/bin/time -l`: 120.43 seconds elapsed, 0.84 seconds user + 0.59 seconds system CPU, 21,626,880 bytes maximum RSS, 0 swaps, 10,355,408 bytes peak memory footprint. These are process measurements with no ASR or actual microphone and no energy claim.

## Remaining evidence boundaries

Physical lock/wake/hot-unplug/TCC changes were not induced. The final installed app, actual audio device, live Apple Speech callbacks, real cloud endpoints and real speech accuracy remain separate acceptance scopes. `SpeechRecognition.swift` was reviewed but not modified; existing local speech queue bounds, input-finalization watchdog and accumulator tests do not prove live service availability. No claim is made that this limited review excludes every device/OS race.
