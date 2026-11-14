# 783921b first CI run — FAIL, wire evidence retained

Source `783921b557b5d6aa1631c5015eb361ac41606dcb`. Four of five jobs passed. No CI rerun or code changes were performed by this monitor.

The localhost protocol suite failed only wizard `churn` at lines 304/305 (completion/services) and 315 (complete PCM/EOS). The hard 12-second watchdog cancelled the checker after 12.2616 seconds. Actual audit: 62 blocks / 198,400 bytes, missing the final 2,306 bytes, EOS=false, one live GPT review. All 52 peer cases report zero protocol violations. Normal/unsupported/each_reconnect wizard scenarios succeeded.

The raw trace shows each intended 100 ms churn block arriving with median interval 215.909 ms and maximum 257.087 ms; the 62 blocks span 11.749 seconds. The other three wizard scenarios delivered the complete 6.272-second sample in 10.881, 11.636 and 11.084 seconds. `CloudConnectionVerifier` sleeps relatively after every block, accumulating scheduling delays. This connection-check replay path is distinct from physical microphone capture. A monotonic absolute clock keyed to cumulative PCM time is the targeted correction; keep the deadline and all byte/hash/EOS/quality assertions. Exact host scheduling source was not measured and should not be invented.

Newly uploaded `protocol-artifact/` contains the full `wire-audit.json`, `server.log` and network test log. `wire-timing-analysis.json` derives each wizard timeline. Server log includes HTTP closing-transport exceptions from closed fixture requests; there is no ASR server crash, and subsequent cases continue. The three ZIP SHA-256 values match GitHub metadata.

Actual tests this run: **17 executed, 16 passed, 1 failed, 3 issues**. Remaining **506 NOT_RUN**: 12 verification + 8 playback + 486 remaining. AppModel and all later native UI/timeline/boundary/package checks also NOT_RUN. Foreground passed; VM hardware sleep/wake remains BLOCKED. These scopes must not inherit the earlier 523/172 success counts.

See `receipt.json`, `failure-excerpts.log`, `pacing-source.txt`, full native log and `SHA256SUMS.txt`. The prior failures remain in their original separate directories.
