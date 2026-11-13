# Qwen preview compute in build 442

The time traces on the packaged 442 helper use the system monotonic clock around every call to the pinned greedy model. The 25.74 s public FLEURS fixture made 43 preview calls and one final call. Read cumulatively, the previews fed 498.5 s of overlapping context to the model and spent 11.100 s in inference. No individual call exceeded 0.472 s. Between publications at 13.520 s and 15.564 s, two calls returned the previous text, the worker produced a new place name at 15.040 s, and it revised that name by one character at 15.558 s. The rendered changes were at 13.549 s and 15.570 s.

The 38.8 s public fixture made 74 preview calls and two final calls. The previews processed 947.1 s of overlapping input and took 20.868 s. The longest call in this replay was 0.710 s. The 15-clip panel trace also contains one identical-PCM final call, at 204,800 frames in FLEURS 0ebe0fb634f8e4ac, which took a further 0.233 s. These are aggregate inference wall seconds and repeated audio context lengths. They do not profile individual operators.

The candidate uses the identical full-context greedy parameters. The pinned decoder synchronizes its GPU stream and frees spare buffers at the end of each call. The small-model worker opts into keeping its bounded 32 MiB pool across previews, clearing at EOS or exit. If the final PCM sample count matches the preceding decode in the same append-only utterance, the worker returns its literal result (including an empty result). An additional PCM frame always permits a fresh final decode. The real protocol probe fixes both paths and a subsequent empty utterance using one public WAV.

Preflight on the M5: `scripts/prepare-local-runtime.sh` applied to the pinned source twice yielded the same Qwen source SHA-256, c9fc8d4b238e87c658e505c51d9834b5ef116e8a554e16244d9e45be7b14da37. The release helper built with Swift 6.4 and its pre-signing SHA-256 was bf75ba594c6fea098250fdcc9481493b7c3627be2affd09c0b94c140e3dc57e8. The existing framed-pipe native probe passed its partial packet, EOS, EOF and ownership checks. Resource and visible-cadence conclusions require the separately paired product runs.

Reproduce from the candidate checkout:

```sh
scripts/prepare-local-runtime.sh
swift build --package-path native/LocalASR --build-system native --only-use-versions-from-resolved-file -c release --product SaytileModelWorker
python3 tests/fixtures/QwenWorkerFinal.py --app "$app" --weights "$weights" --audio "$public_wavs"
```
