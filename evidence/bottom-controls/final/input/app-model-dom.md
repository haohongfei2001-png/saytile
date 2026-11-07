# AppModel and headless DOM checks

The production AppModel probe passed **104 checks** on `455143310222c2c03c4a4888e5df5552c3af4131`. It used isolated stores, injected capture/connection actions and the exact new SaytileKit static library from the full native build. The source and executable hashes are recorded in `app-model-identity.json`, with the full log in `app-model.log`.

The headless browser probe passed **20 checks** against its loopback fixture. The Swift coordinator, SQLite reservation and UTF-16 range handling were production code. Target discovery and editing used the isolated DOM adapter. The Chromium process used a fresh browser context and no user profile. The Chromium and owned probe binaries matched their before/after hashes. `browser-identity.json`, `dom-binary-identity.json`, `browser-run.log` and `input-browser-dom.log` preserve the exact browser, Playwright version and observed results. Native AX and real foreground input have separate acceptance evidence.
