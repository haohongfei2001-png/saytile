# Foreground readiness failure and correction

Product binary: 0.21 (557), source `9aace8f5b0d7082bd67d2e9b1b6e1db6dcf05883`.
Failed run: https://github.com/haohongfei2001-png/saytile/actions/runs/45082257079
Job: 137392813208. Original full log and artifact ZIP are retained alongside this file.

The first post-bind WKWebView sample retained process, application, window, editor,
caret, range, editability and setter identity. `pageContextComplete` changed from
true to false and page identity differed, with zero observer notifications; the
binding was still current. No insertion had been attempted. The fixture explicitly
invalidated the binding because it equated an incomplete observation with changed
page evidence. The log cannot establish which bounded AX traversal read expired;
no claim of a particular OS timeout or focus competition is made.

Fix is confined to fixtures. An incomplete context may reset the quiet-read counter
only when the retained URL/title and every other independently readable property
still match. Missing identity, changed URL/title, window, editor, caret, selection,
security or editability still abort. The existing five-second overall deadline and
three fresh complete identical observations, live observer, exact original text
witness and single activation/binding remain. There is no write retry, rebinding,
focus reacquisition, skipped assertion or product safety change.

PASS: standalone compiled Swift fixture policy, 17 cases, including all independent
identity mutations. This is a deterministic readiness-policy regression, not a
replacement for real AX. The updated real WKWebView/AppKit/Chrome/TextEdit workflow passed on
94db534265597e4bc26109e2d849b2406f62edb3, run 45083846290, foreground job
137397822049. All six jobs passed; the original failure remains preserved.

The failed run's Chrome, Chrome interrupted-focus confirmation and TextEdit logs
remain in the artifact ZIP; they do not turn the failed WKWebView batch into PASS.


## Second observed failure: d03f446

Run 45086450912, foreground job 137406069438, failed before first insertion. Original log/ZIP are `foreground-failed-d03f446.*`. This time every outer snapshot matched and the fixture logged `witness_missing`; binding was still current and observer notifications were zero. Production `textWitness` does bounded text and before/after identity reads, returning nil if any proof is unavailable. The log cannot identify which inner read was unavailable. The contemporaneous NSSpellServer timeout is retained, not asserted as a cause.

The same readiness bug also existed for missing text witnesses: initial reads correctly waited for full evidence, but post-binding readiness treated nil as a changed readable value. The fixture now distinguishes ready / absent / changed. Only absence after an exact matching outer snapshot resets quiet count within the original five-second deadline; a different readable value (including byte-different Unicode), changed target or invalidated observer still aborts. No write, rebind, focus action, added deadline or skipped assertion occurs. Three complete exact reads are still required.

PASS: compiled deterministic readiness policy 22 checks (the original 17 plus missing/exact/empty/manual-edit/Unicode-byte witness cases). The real native AppKit and WKWebView batches each inject exactly one missing *fixture-readiness* witness after binding, require zero writes before readiness, then use the normal unchanged production checks for insertion. Production witnesses are never intercepted. Actual updated foreground CI must succeed on the PR head; 94db534's previous success is not substituted for it.


## Third observed failure: 09e5877; production AX reads

Run 45087394247, foreground job 137409103330. Full original log and artifact ZIP are `foreground-failed-09e5877.*`. WKWebView failed inside production `bindCurrentTarget` when its empty-range witness was unavailable, before insertion; this is distinct from the prior fixture readiness classification. Chrome's first write was exactly observed, but subsequent content notifications lost complete ownership confirmation. No automatic send or replay occurred. The original log does not identify the unavailable inner read.

The candidate now batches the same non-value AX attributes for field identity, ancestor identity and context nodes to reduce serial cross-process calls. Semantic values are still read only after classifying noneditable anchors. The 150 ms complete-context budget, 120 ms message timeout, complete page digest, exact text/caret/window checks and observer invalidation remain. Transport failure in ancestry fails closed, including a WKWebView hosted by a nonbrowser app. There is no proof cache, write retry, automatic focus action, rebind or relaxed observer policy. Optional fixture diagnostics contain reason labels only.

Local compilation and the same 22 deterministic fixture-policy checks PASS. The nonactivating local native batch exits 2 before AX setup because `NSRunningApplication(processIdentifier:)` cannot establish the bare fixture's process identity on this host; it does not prove the product passed or failed. No activation or permission change was attempted. Real CI verification and a newly source-bound package are required for the product change. Previous 557 package evidence remains frozen.
