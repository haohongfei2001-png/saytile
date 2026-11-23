# 0.23 Qwen experience closure

Baseline: PR #54 product `5ebff045ff10c34dbbe12ce5235e3cef4f6d07a0`, evidence head `99526a8f4175d3808c828aa2b75ac5c5f6642d1d`.

Scope: first output, provisional revisions, native panel continuity, safe external input. Installed 533, main, personal data, original evidence and release channels remain untouched. No new recognizer, notarization or public release.

Product candidate: `a1ac008de50855ae0c03f30128f5b1f74269d617`, 0.23(571). Diagnostic build 570 is retained separately. Subsequent fixtures and receipts do not change this product source.

1. PASS (bounded improvement): startup timeline identifies tokenizer loading as a substantial cold-start cost. Native JSON decoding, reserved map capacity and equivalent UTF-8 merge parsing reduce tokenizer CPU in three alternating pairs. All 152000 checked token IDs and 440 reference encodes remain identical. Same 15 real-rate native clips: visible first-text P50 2.242 -> 1.630 s, P95 3.271 -> 2.681 s, 46/568 errors unchanged. This shared-host result is not proof of restoring the historical 1.563 s P95.
2. NO-GO: replayed whole-candidate correction throttles reduce some ABA but delay fresh speech, including up to 1.2 s for deep corrections. They remain offline prototypes; no production throttling or candidate splicing is added. Current paired 15-clip ABA remains 2 -> 2; historical 1 -> 9 is retained, not reclassified.
3. PASS (current observations), UNKNOWN (historical cause): 16/16 final native windows match archives with 4953 new surface observations and no reported blocker. Controlled selection/edit/reading/hidden/control-only replay recovers all 18 finals; one of 252 rapid 120 ms intermediate samples remains FAIL, retained in controlled-summary.json. Neither result proves the historical multi-second visible-stop cause. No ownership guard is weakened.
4. PASS (safe EOS-only input), limitation remains: 13 actual Qwen partials produce no dispatchable revision and no AX edit; the original EOS inserts exactly once into an owned background NSTextView with surrounding content intact and zero keyboard/send events. This accelerated replay is not a fresh latency benchmark or foreground-resolver test. Two/three/four-observation prefixes conflict with EOS in 11/7/6 of 23 sampled segments; those heuristics are not promoted.
5. PASS: 440-clip quality, 440 identical finals/states, original420 CER 8.53%, derived20 CER 8.51%; signed package/read-only mount/isolated offline launch. Gatekeeper BLOCKED (task prohibits notarization). Complete Xcode CI PENDING final head. Historical CI does not certify this source.
6. Idle reload verified from raw native observations: two identical final strings, worker absent after 37 seconds of quiet and loaded again on speech. Original generic harness FAIL retained because it concatenated two paragraphs without the required newline; separate exact two-paragraph assertion passes. This diagnostic is not a paired latency benchmark.

Raw native AB/BA runs: `paired16/`, 32 arms, no process failures. Summary: `comparison.json`. CPU across normal 15 clips is 91.75 -> 86.53 CPU-s, a small shared-host observation, not a demonstrated steady-state inference CPU improvement. The 38.8 s long sample still has a 2.214 s internal visible gap; that limitation remains.

Initial finding: in the mixed-speech outlier pairs, the 569 worker was ready about 0.3–0.55 seconds later than 567; first decode was 0.14–0.24 seconds. Model startup, not database or AppKit, dominates these particular regressions. This is an observation, not yet a causal optimization result.
