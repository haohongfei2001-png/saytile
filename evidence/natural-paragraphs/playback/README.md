# Natural paragraph original-audio playback

This is independent generated-silence validation; no user recording, microphone, ASR, paid service or installed application was used. The exact changed-source hashes and compiled object hashes are in `receipt.json`. The package was dirty against the declared base while the integration branch was under development; the complete frozen candidate must additionally pass its CI.

**PASS: 10 Swift Testing tests, 10 passed, 0 failed, 0 skipped** (four inherited and six new). The official local `Testing.framework` runner called the actual checked-in test file and freshly compiled `SaytileKit` objects; no assertions were replaced by a simulator.

The actual AVAudioPlayer tests cover ordered playback across original recording boundaries, aggregate seeking and progress, immutable paragraph identity, duplicate ID suppression, missing/deleted/unreadable files, all originals unavailable, deletion of an original queued for later playback, release of erasure leases, switching paragraphs, cancellation of an asynchronous seek, and pause while a later original is awaiting validation. Native player completion actually advanced from one original to the next. Pausing never resumed capture. Original text remained after raw-audio deletion.

The initial sandbox execution could not start any system audio player: both inherited playback integration tests and all five initial paragraph cases failed at `play() == false`. The same binary succeeded with normal existing macOS service access. The final run adds deterministic pause-during-validation coverage and passes all ten tests. No privacy or security setting was changed. The public build interface remains unchanged; the internal recording lookup injection only makes the real asynchronous cancellation boundary deterministic in the regression.

Full-Xcode targeted reproduction:

```sh
scripts/test-native.sh --no-parallel --filter 'AudioPlaybackTests|AudioPlayerIntegrationTests|ParagraphPlaybackTests'
```

`AudioController.play(recordingIDs:playbackID:)` expects chronological original IDs from the archive paragraph. `playingID` is the paragraph identity; `playingRecordingID` is the original currently played. `playbackNotice` reports unavailable originals only in the archive/settings host. Raw files are neither concatenated nor rewritten. The currently open journal is closed before its final chunk lengths are read, preserving its saved tail. The existing single-recording API delegates to the same playback path.

The 15-second paragraph gap may use the existing `TimelineEntry.speechEnd`: it already excludes the configured 1.5-second local (2-second cloud) silence tail. It still includes WebRTC classifier hangover, generally a small fraction of a second, because `STVoiceHangover` resets the segmenter's quiet counter. The implementation does **not** subtract a guessed fixed duration and does **not** alter VAD or ASR behavior. This boundary is derived from detector evidence, not a claim to know the exact semantic end of speech.
