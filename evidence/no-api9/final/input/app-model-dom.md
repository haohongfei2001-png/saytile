# no-api.9 AppModel and headless input

The real AppModel passed 104 checks on the isolated store, injected capture and connection actions and freshly built SaytileKit from `dc26fe3c59ba55994d29e99ada8d2f0b49ad9886`, tree `f138f6733a642a2e53da22b3647aaf5744cb308b`. `app-model-identity.json` preserves the executable, library, source and raw result hashes.

The production Swift coordinator and SQLite reservations passed all 20 checks in an isolated headless Chromium context. Textarea and contenteditable targets covered UTF-16 suffix insertion, duplicate suppression, selected text, navigation, focus loss and zero sends. Target discovery and field editing used the test-only DOM adapter. The browser and probe binaries retained their pre-run hashes. `browser-identity.json`, `dom-binary-identity.json` and `input-browser-dom.log` record the exact browser and individual outcomes. Native AX checks are recorded separately.
