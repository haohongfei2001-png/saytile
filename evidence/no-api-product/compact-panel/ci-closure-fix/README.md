# Render-only closure dispatch repair

The exact `a6849128` native CI run failed at `panel-content` after its native/protocol, AppModel and release build checks passed. Complete original CI logs and terminal failure remain in `final-no-api4/protocol/`; the original workflow was not rerun. The CI runner used Swift 6.3.3. Its render-only command had no AX control helper, as intended, but a legacy trailing closure bound to the newly added optional `validation` argument and ran control actions unconditionally.

This was not demonstrated to be a compiler-version discrepancy. The isolated `closure-binding.swift` reproduction on local Swift 6.4 also prints `ORIGINAL validation=true interaction=false`. Earlier local `--controls` checks supplied the helper and therefore concealed the incorrect mode dispatch. The local mode-coverage gap is an explicit limitation of that earlier result.

The repair restores `reviewWindow` to its single optional interaction closure. Its implementation forwards to the distinct `reviewValidatedWindow` entry point. Only the long-text fixture explicitly calls the latter with both labeled closures. No assertion, action, timing bound or production UI behavior was removed or weakened. The minimal reproduction now prints `REPAIRED interaction=true`.

One new preview was built at `/tmp/saytile-compact-closure-preview/Saytile.app`; the prior a684 package was retained. Both modes ran against that same new binary:

| Mode | Result |
| --- | --- |
| Render-only, matching CI's invocation mode | PASS; 20 native captures, zero AX controls/helper actions; actual native text/selection/scroll and UTF-16 checks each ran |
| Native controls | PASS; 31 captures, 41 AXPress, 6 native menu selections, 5 capture-control inspections, 6 AXSetValue, 6 field edits including 3 secure fields, 12 control groups, one actual resume acknowledgement |

Both runs recorded zero outside foreground transitions and rejected candidate activation. The injected capture lifecycle remained separate from the real microphone. Connection fixtures used synthetic credentials and an injected TEST_ONLY receipt, with no real provider call. All evidence is a dirty preview based on a684 plus this repair, not a new committed source identity or successful final CI. `verification.json` binds the exact source and binary hashes and detailed counters. A new frozen source requires its own final checks.
