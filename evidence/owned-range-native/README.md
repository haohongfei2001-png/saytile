# Owned-range native AX acceptance

Dedicated test addition for `NativeInputCoordinator.repairOwned`, production
`AXInputAccess` (the actual class name), and `SaytileStore`. No production source
changes. The script directly compiles all current `Sources/SaytileKit/*.swift`
and the production CAudio C/C++ sources into static SaytileKit with testing enabled,
then links the probe against that library. The C exclusion matches `Package.swift`;
no SwiftPM manifest, sandbox-disable flag or source rewriting is involved.
It never uses an old installed
app or an already-built binary as evidence for the current checkout.

Run once after parent integration on macOS, with **already available** AX access:

```sh
python3 scripts/test-owned-range-native.py --execution-context unsandboxed
```

Compile without starting either the probe or fixture:

```sh
python3 scripts/test-owned-range-native.py --compile-only --execution-context sandbox
```

`--execution-context` is an evidence label, not an elevation switch. The script
cannot escape a sandbox or grant permissions. Exit 5 / `BLOCKED` means permission,
sandbox, or native fixture prerequisites were unavailable. It never calls the
permission-prompt API, launches System Settings, changes TCC, or retries after
unknown delivery. Compile-only returns 0 with `native_ax=NOT_RUN`, never an AX pass.
Other failures return 1. Only a complete native probe run returns `status=PASS`
and `native_ax=PASS`. Do not reinterpret sandbox failures as passed acceptance.

Each invocation creates a mode-0700 `/tmp/saytile-owned-range-native-*` directory.
Its `summary.json` records source hashes, checkout HEAD, execution context, and
separate compile/native verdicts. Build logs, `preflight.log`, `probe.log`, and
five independent synthetic SQLite stores stay there for inspection. The script
prints that evidence path. It does not overwrite repository evidence or silently
reuse/delete an earlier run. Only spawned child processes are terminated on exit.

## Real OS scope

The receiving app is a dedicated, prohibited-activation, offscreen NSPanel with
two real NSTextViews. Successful setters call NSTextView's `super` implementation.
Receiver-side overrides count selected-text/range calls and reject/log forbidden
whole-value/key/paste attempts. This is **not** a fake `InputAccess`: the production
adapter makes cross-process AX calls, registers real AX notifications, and reads
the parameterized AX string-for-range witness. Capability gating prevents the
insertion adapter from taking its clipboard fallback. Clipboard content is never
read; only its change counter is compared. Concurrent clipboard changes fail the
test without attributing their cause.

Only target selection is injected, returning the exact fixture process and one
of its two controls. The Python parent supplies its spawned PID plus a fresh
nonce; the probe checks the executable path and nonce-bearing window/identifiers,
and checks each traversed AX node's PID. No user application's AX tree is opened.
The existing activation audit helper is linked read-only to observe process
identity transitions, not external application content. No fixture/probe activation
is permitted. No microphone, screen capture, cloud/provider request, real document,
preferences, production archive, or existing database is accessed.

This certifies a dedicated background native target **only**. Production foreground
selection, installed-app TCC identity, third-party editors, browsers, and real
speech/ASR accuracy remain outside this test. Synthetic complete candidate evidence
is published via production Store/Fusion APIs; no paid API or fabricated SQL
ownership row authorizes the correction.

## Required scenarios and assertions

All cases first confirm `50😀` inserted between `用户前缀😀｜` and `用户后缀🚀`.
The emoji in the user prefix also distinguishes UTF-16 offsets from character counts.

| Scenario | Required native result |
| --- | --- |
| Repair and continue | `50😀` → `500👩🏽‍💻`, exact original owned range, one selection setter and one text setter; prefix/suffix preserved; caret verified; correction journal confirmed once |
| Continuation and duplicate calls | Only `，后续。` appended at corrected UTF-16 end; duplicate repair and append create no setter calls; SQLite contains original and suffix dispatches with contiguous monotone ledger coordinates |
| Manual user edit simulated inside fixture | Replace `50` with `99`, retaining caret and UTF-16 length; repair stays pending with zero correction setters and edited text preserved |
| Selection change | Fixture selects existing user prefix; repair stays pending with zero correction setters |
| Target change | Inject selection of the fixture's second real NSTextView; neither control receives a correction setter |
| Setter refusal / uncertain completion | Fixture drops the one selected-text replacement after accepting the range setter; production confirmation fails, journal is unverified; repeated API call makes zero additional setters |

For every scenario the alternate control remains unchanged, whole-value/key/paste
counters remain zero, and refused correction archives remain available. Repeated
public API invocations are deliberate no-replay assertions; the harness itself
does not retry a mutation. Every setup reset/manual edit occurs via private fixture
IPC, separately from counted AX setters. Sender and receiver assert exact text,
ranges and counts; partial progress cannot produce the final pass marker.

## Integration

Requested base: `c4c74e6`. The assigned branch was already at `d361f1e` on entry
(a descendant containing an existing failover integration test); that commit was
preserved. Parent should cherry-pick this dedicated test commit and run the command
once at the final integration HEAD. No push, merge, CI wait, or deployment is needed.
See `RESULTS.md` for actual local execution and remaining blocker.
