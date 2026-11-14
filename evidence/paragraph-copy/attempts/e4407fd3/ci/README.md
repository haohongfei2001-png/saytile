# PR 43 diagnostic revision CI receipt

Source `e4407fd3df7a62bbc6db1685a4de9ae6c417788c`: all five jobs PASS. Swift Testing actual 525/525 (4+13+12+8+488), AppModel actual 183 checks. Logs and artifacts are original GitHub output, with platform-generated credential redaction retained. No rerun, source edit, App launch or installation by this collector.

**Previous failures remain NOT_ROOT_CAUSED.** The earlier `8ffa4461` Chrome target-switch bind failure and runtime exit141 did not recur in this diagnostic-only run. A passing run is not proof those faults were fixed. Their original logs remain under `/private/tmp/saytile-paragraph-copy-release-8ffa4461/ci/`.

CI natural-paragraph checks PASS for 21 scenarios, but the remote AX control probe was not configured: nativeControlActions and panelButtonAX explicitly NOT_RUN. Real NSMenu archive copy was exercised. This is narrower than the parent's signed local 22-scenario AX acceptance. Hardware sleep is BLOCKED on VirtualMac2,1; physical second-display drag and native fullscreen are NOT_RUN. No actual microphone or paid-cloud ASR verification is claimed.

`summary.json` contains exact links, counts, limitations and evidence paths; `SHA256SUMS.txt` binds all retained files. The next fixture-only source is a separate CI subject and must not borrow this SHA's PASS status.
