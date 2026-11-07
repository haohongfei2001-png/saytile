# Frozen 1067f1ad input and AppModel verification

Runtime `1067f1ad5c5c29c698f346651c965db2169625eb`, tree `1c59b5e95f92dd34b19d4fb390549724071114a6`. Before/after identities show all 201 source inputs unchanged and no tracked runtime/test/script edits. Executed AppModel, four native fixture/probe binaries, DOM probe and headless Chromium hashes were unchanged. Fresh scratch directories and isolated synthetic data were used.

| Verification | Actual result | Boundary |
| --- | --- | --- |
| AppModel | 78 checks passed | Injected capture/connection dependencies; no microphone or real cloud evidence |
| Headless DOM | 20 checks passed | Production coordinator + Store + test DOM adapter; fresh headless context, no user browser profile; not native AX |
| Native insertion | Original 9 checks passed | Actual owned AppKit AX setters and injected target selection |
| Independent target change | 5 checks passed | One production setter + one explicitly separate fixture edit; unverified, invalidated binding, no owned range, no replay |
| WKWebView observation | 6 checks + 2 capability rejections passed; sends=0 | Actual insertion remained **unverified**: AX setter acknowledged, DOM unchanged; no replay or browser-success claim |
| Owned range | 9 scenarios passed | See `../owned-range`; focus case uses real first-responder IPC through existing selection seam, not certified foreground AX notifications |
| Local Apple Speech | 8 synthetic cases completed | See `../apple`; actual transcription errors retained, no human-speech or cloud accuracy claim |

Both native/WK fixture receipts recorded key=false, main=false, keyboard_events=0, owned_activated=false. In this run the observed foreground identity remained unchanged and no outside activation events were observed. Fixtures were transparent, ignored mouse input, and were cleaned up. These bounded observations do not certify all third-party applications, installed Saytile's own TCC identity, or the production foreground resolver. Historical UNKNOWN/unverified limits and a6849128 HOLD failures remain intact.

`receipt.json` provides the machine-readable results and links to source/binary evidence. Evidence-only wrappers retain or hash the actual executable while invoking the unchanged repository test scripts. No runtime files were changed, no microphone opened, no provider request made, and no global keyboard input or user target was used.
