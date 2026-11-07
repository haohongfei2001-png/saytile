# Silent playback progress timing

The frozen full suite recorded exactly one failure. A 1.6-second synthetic silent recording started successfully, but `playbackPosition` was `0.0` at the test's single observation after sleeping 180 ms. Its duration, subsequent chunk seeks, deletion lease release and retained text checks all passed. The original run recorded no timestamp for the first positive publication, so its precise scheduling history is unknown.

The production player publishes position from `AVAudioPlayer.currentTime` after its main-actor progress task runs and sleeps for 100 ms. The 180 ms test sleep starts in a different task. It cannot guarantee a positive publication by the time the test samples the property.

`PlaybackDiagnostic.swift` ran once against the actual Debug SaytileKit library from the frozen full run. The program used the same 1.0-second and 0.6-second silent chunks. A controlled main-actor occupancy of approximately 230 ms was queued before the production progress task's first sleep. This intentionally supplied one reproducible scheduling order in an isolated process. The first diagnostic compile needed `@testable import SaytileKit` for the repository's internal PCM journal. Its compiler output is retained separately. The corrected diagnostic was the only playback execution from that program.

| Observation | Seconds since program timing origin | Result |
| --- | ---: | --- |
| Production `play` returned | 0.577106 | Active recording, duration 1.6 seconds |
| Original single sample | 0.808969 | Position 0.0, recording still active |
| First actual positive publication | 0.911431 | Position 0.301875 seconds |
| Seek and lease checks | After the positive publication | Both cross-chunk seeks, deferred deletion, stop/release, deletion and text retention passed |

The experiment demonstrates a normal player that fails the old one-time observation. It does not reconstruct the original machine's exact task schedule. No production playback change was needed for the observed case.

The revised test subscribes to the first real positive position before calling `play`. It waits until that event, player stop or a two-second monotonic deadline. It requires timely publication, the same active recording and a positive current position before seeking. The original duration, seek, lease, stop and retained-text assertions remain.

A separate test scratch compiled and executed the revised `AudioPlayerIntegrationTests` once. Both functions passed. The seek case received actual position **0.0856875 seconds**, **0.10681175 seconds** after `play` returned. The natural-completion case also passed. `fixed-target.log` and `fixed-target-driver.log` belong to the revised test source after 702a. `run.log` and `identities.json` describe the controlled diagnostic against the frozen library. All audio was silent synthetic data from independent temporary directories.
