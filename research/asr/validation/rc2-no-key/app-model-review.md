# Coalesced archive refresh and shutdown boundary

The production AppModel awaited a shared pass, then recursively called refresh() for each waiting caller. Each recursion minted another request version, so a burst of 40 notifications caused 40 sequential database passes. This is avoidable work on the same main actor that renders temporary text and schedules stable input.

The red AppModel probe actually observed callers=40/database_passes=40. A waiting caller now retains its original version; one next pass covers all requests admitted before it began. Task identity still prevents an old waiter from clearing a newer operation. Late requests after successful exit preparation are rejected before touching the closed Store. The counter records actual read passes, not synthetic calls, and is not published to the interface.

The same burst now observed 2 database passes while archive contents remained correct. The complete existing AppModel probe plus two new regression checks passed 25 checks, including draft preservation and shutdown. This is a deterministic work-count improvement, not a measured whole-system power or live-cloud latency claim. No native input target, clipboard, microphone or network was used. The pipeline reviewer independently reviewed the version/task-identity/exit logic without findings.

Evidence: app-model-before.log (actual failure), app-model-after.log (25 checks). Root will run integration after all module changes freeze.
