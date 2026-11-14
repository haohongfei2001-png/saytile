# 3b60b66 full CI — native PASS, foreground FAIL retained

All results bind `3b60b66295070cffbc34ed2486e53c1dc33e5b98`. **4/5 jobs passed; native completed successfully.** The only failed job is foreground Chrome first-insertion confirmation. No rerun, source modification, user desktop action or installation was performed by this monitor.

- **Swift Testing 523/523 PASS**, 0 failures: groups 4 + 13 + 12 + 8 + 486.
- **AppModel 172 checks PASS**.
- **Protocol 52 cases / 0 violations**. All four wizard arms delivered exactly 200,706 bytes with expected SHA-256 and EOS=true. EOS times: 6.271 / 6.320 / 6.290 / 6.275 seconds. Before: 10.881 / 11.636 / timeout before EOS / 11.084 seconds. Churn median block interval: 215.909 → 102.635 ms. Deadline and evidence assertions were unchanged. Raw audits and `wire-before-after.json` prove this improvement.
- **Natural paragraphs 16 checks PASS**: 4 synthetic originals, 3 paragraphs, 2 time groups, real AppKit editing and AVAudioPlayer silent playback. Pointer star/play control actions **NOT_RUN**; no ASR or microphone.
- **Native timeline 12,003 rows / 64 resident PASS**: zero idle shift, 1-point paging anchor, no horizontal/shear displacement, 0.027926625-second wheel-to-paint, exactly one midnight paragraph newline, original text preserved, no time heading, stable selection and isolated history. Private pasteboard pointer/click path was not configured in hosted review; parent holds separate local AX-copy acceptance.
- **Panel boundary 20 checks PASS; native fullscreen NOT_RUN** in CI. Prior platform observations remain labelled as historical evidence.
- General UI rendered 33 native captures; interactive controls **NOT_RUN**. Startup smoke passed with zero records and 200,706-byte bundled sample.
- Actual hardware sleep/wake **BLOCKED** by VirtualMac2,1 capabilities.

## Foreground failure

Isolated AppKit/WKWebView and TextEdit passed. Chrome had 3 complete plus 3 quiet bound reads, exact DOM/caret, and two full production snapshots before one 20-ms write. Its content/selection event then encountered `unsupported` during production snapshot; the binding invalidated and returned `unverified`. Independent AX text readback was exact, with exactly one write and zero automatic send. This is successful mutation followed by failed confirmation, not duplicate or wrong-target insertion. The specific unavailable AX field was not recorded. Parent is preparing a separate narrowly guarded fix; this run remains FAIL.

All five small ZIP artifacts match GitHub-advertised SHA-256. General UI ZIP download ended once with unexpected EOF; partial bytes are retained as `.partial`, marked **not downloaded**, and not presented as visual evidence. The full native log independently retains the completed UI/timeline results. Large unsigned candidate ZIP was intentionally not downloaded; signed local candidate acceptance is separate.

See `receipt.json`, complete logs, extracted machine artifacts, `wire-before-after.json`, and `SHA256SUMS.txt`. Previous failures remain untouched in their original directories.
