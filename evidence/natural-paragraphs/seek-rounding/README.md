# Exact native seek rounding reproduction

The signed 481 candidate passed its owned native paragraph checks, but CI attempt 2 failed the strict `playbackPosition >= 0.9` assertion while running 494 tests concurrently. The playback test lasted 8.522 seconds for a 1.6-second fixture.

A separate native probe reused the same compiled SaytileKit and the same synthetic 0.4/0.3/0.9-second WAV structure. Across eight seeks, one actual progress tick published `0.8999999999999999`, while AVAudioPlayer.currentTime was exactly `0.2`; the second recording and paragraph identities remained correct. This is one Double ULP from the sum `(0.4 + 0.3) + 0.2`, not an audio frame lost or a playback jump. Full timestamped observations and the probe are retained here; there was no microphone or private archive access.

The test now asserts immediate seek is exactly 0.9, then allows only its single nextDown value at the subsequent real progress observation. The upper bound, ownership, missing-file, lease and deletion assertions remain. Real-player tests run in their own process, with all tests retained, so unrelated main-actor work cannot consume the tiny playback fixture's observation window. No production playback code changed.

The earlier protocol timeout did not recur in local or controlled CI reproduction. Its exact cause remains unproven. Future CI now uploads the existing local wire audit and server log on failure as well as success; no deadline or protocol assertion changed.
