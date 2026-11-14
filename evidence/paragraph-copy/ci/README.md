# PR 43 final 0.17 (488) CI receipt

Source `58bc8f96f79942881d1ae3221fd6219635833907`: all five jobs PASS. Swift Testing actual 525/525 (4+13+12+8+488), AppModel actual 183 checks. Zero Swift test cases skipped; zero dependent workflow steps skipped. Logs and artifacts are original GitHub output, with platform-generated credential redaction retained. No rerun, source edit, App launch or installation by this collector.

**Previous failures remain NOT_ROOT_CAUSED.** The earlier `8ffa4461` Chrome target-switch bind failure and runtime exit141 did not recur in diagnostic revision `e4407fd3` or this final revision. These successful runs do not prove the earlier faults were fixed. Original logs remain under `/private/tmp/saytile-paragraph-copy-release-8ffa4461/ci/`; e440 evidence remains separate.

CI natural-paragraph checks PASS for 21 scenarios, but the remote AX control probe was not configured: nativeControlActions and panelButtonAX explicitly NOT_RUN. Real NSMenu archive copy was exercised. This is narrower than the parent's signed local 22-scenario AX acceptance. Hardware sleep is BLOCKED on VirtualMac2,1; physical second-display drag and native fullscreen are NOT_RUN. No actual microphone or paid-cloud ASR verification is claimed.

`summary.json` contains exact links, counts, limitations and evidence paths; `SHA256SUMS.txt` binds all retained files. These results are bound only to the source above. The collector performed no installation.
