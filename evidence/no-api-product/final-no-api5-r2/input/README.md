# Input and controller verification

Runtime `4df87ad4dd7ff94da2027f0c978ca5c5cb1d7292` and tree `ce2a3fed6a27a96ed4dca80abeac307793d4e705` had clean tracked inputs at both source-identity samples. All 204 tracked source, fixture, script and packaging inputs had the same digest before and after execution, `f30a53d3f37111f773928c4074ae1986b31888c12969882ad0a0174692a3a22d`. AppModel, all four native fixture/probe executables, the DOM probe and the dedicated headless browser executable retained their hashes. [Receipt](receipt.json)

| Layer | Result | Observed behavior |
| --- | --- | --- |
| AppModel | 97 checks passed | Production controller and isolated Store. Connection and capture actions use injected dependencies. |
| Headless DOM | 20 checks passed | Production coordinator and Store exercised through a DOM test adapter in a fresh localhost browser context. |
| Native AppKit AX | 9 original checks passed | The real setter inserted only the stable suffix in a dedicated background text field. Selection changes invalidated its binding. |
| Target change after the setter | 5 checks passed | One production setter and one independent fixture mutation left the result unverified, with an invalidated binding, no owned range and no replay. |
| WKWebView | 6 observer checks, 2 capability refusals, 0 sends | The setter acknowledged the insertion request. The DOM stayed unchanged. Delivery remains **unverified**. |
| Owned-range AppKit AX | 9 scenarios passed | Foreground resolver status remains `NOT_RUN`. [Owned-range results](../owned-range/README.md) |
| Apple local recognition | 8 completed synthetic cases | Per-case outputs, timings and critical omissions are retained. [Apple results](../apple/README.md) |

The native and WK fixtures remained non-key and non-main, received zero keyboard events, and reported zero owned activation or outside foreground transitions. The headless browser used the existing Playwright shell with a fresh context and no user profile. The WK log retains the unverified delivery. Production foreground input, third-party app compatibility, installed application TCC identity and the historical `UNKNOWN` cases retain their prior boundaries.

Source identities are in `source-identity.before.json` and `source-identity.after.json`. The retained evidence runners invoke the existing fixture logic and capture hashes of the executed binaries. The ordinary native, WK and owned-range fixtures ran serially. No cloud provider or microphone was used.
