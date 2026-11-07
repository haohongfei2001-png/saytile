# Input and controller verification

Runtime `702a24b9767826275f650c70f7e118365601a2a8` and tree `f5a357a00b97a246ee5c6ee0a95272738c135c0d` were clean throughout these runs. All 204 tracked source, fixture, script and packaging inputs had the same digest before and after execution, `79add2b30abbfe882df7b399e4eb9e6623e9f0f31b7bad51ae35994fe0831ada`. AppModel, all four native fixture/probe executables, the DOM probe and the dedicated headless browser executable retained their hashes. [Receipt](receipt.json)

| Layer | Result | Observed behavior |
| --- | --- | --- |
| AppModel | 97 checks passed | Production controller and isolated Store. Connection and capture actions use injected dependencies. |
| Headless DOM | 20 checks passed | Production coordinator and Store exercised through a DOM test adapter in a fresh localhost browser context. |
| Native AppKit AX | 9 original checks passed | The real setter inserted only the stable suffix in a dedicated background text field. Selection changes invalidated its binding. |
| Target change after the setter | 5 checks passed | One production setter and one independent fixture mutation left the result unverified, with an invalidated binding, no owned range and no replay. |
| WKWebView | 6 observer checks, 2 capability refusals, 0 sends | The setter acknowledged the insertion request. The DOM stayed unchanged. Delivery remains **unverified**. |
| Owned-range AppKit AX | 9 scenarios passed | Foreground resolver status remains `NOT_RUN`. [Owned-range results](../owned-range/README.md) |
| Apple local recognition | 8 completed synthetic cases | Per-case outputs, timings and critical omissions are retained. [Apple results](../apple/README.md) |

The native and WK fixtures remained non-key and non-main, received zero keyboard events, and reported zero owned activation or outside foreground transitions. The headless browser used the existing Playwright shell with a fresh context and no user profile. The WK log retains a system spell-service timeout and the unverified delivery. The evidence does not identify a causal connection between them. Production foreground input, third-party app compatibility, installed application TCC identity and the historical `UNKNOWN` cases retain their prior boundaries.

Source identities are in `source-identity.before.json` and `source-identity.after.json`. The retained evidence runners invoke the existing fixture logic and capture hashes of the executed binaries. The ordinary native, WK and owned-range fixtures ran serially. No cloud provider or microphone was used.
