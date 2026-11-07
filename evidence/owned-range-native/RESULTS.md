# Actual execution — 2026-11-07

**Native AX acceptance: BLOCKED. Zero native scenarios executed.**
The probe returned `BLOCKED AX_PERMISSION_UNAVAILABLE_NO_PROMPT`. The runner
stopped before launching the text fixture. No AX mutation, activation, permission
prompt, TCC change, clipboard write, microphone access or online recognition occurred.

| Check actually run | Result |
| --- | --- |
| Python AST parse and CLI `--help` | PASS |
| Swift frontend parse of both new fixtures | PASS |
| Compile dedicated NSTextView executable | PASS |
| Compile all current SaytileKit + production CAudio sources and static library | PASS; existing macOS 27 deprecation warnings retained |
| Link production-library AX probe | PASS |
| Probe's existing AX permission check | BLOCKED; no prompt |
| Final probe recompile with `-warnings-as-errors` | PASS, exit 0, empty compile log |
| Five real AX scenarios | NOT_RUN due to the permission blocker |
| Third-party apps / real foreground resolver | NOT_RUN; outside scope |

Full run command:

```sh
python3 scripts/test-owned-range-native.py --execution-context sandbox
```

Exit code: **5**. Full retained scratch:
`/private/tmp/saytile-owned-range-native-2kp334uo`.
Committed [sandbox-run-summary.json](sandbox-run-summary.json) records the exact
source hashes for that run; [sandbox-preflight.log](sandbox-preflight.log) contains
the native permission result. [production-compile.log](production-compile.log)
preserves compiler warnings. Compiler/OS/target details and the final probe's
source/binary hashes are in [final-compile.json](final-compile.json).

The full run initially emitted one warning about mutating the target-choice local
after closure capture. The final probe uses a MainActor reference holder and marks
unavailable fixture registration/AX snapshots as BLOCKED. Only this probe changed
after the full run; all production sources and the fixture/runner hashes still
match. It was then recompiled and linked against the freshly built production
library, with warnings treated as errors. The known-unavailable AX preflight was
not retried. The original run summary was not rewritten to imply it executed the
final probe. Exact final compile command (repository root):

```sh
swiftc -swift-version 6 -warnings-as-errors -parse-as-library \
  -I Sources/CSQLite \
  -I /private/tmp/saytile-owned-range-native-2kp334uo/production \
  -Xcc -fmodule-map-file=/private/tmp/saytile-owned-range-native-2kp334uo/production/CAudio.modulemap \
  -L /private/tmp/saytile-owned-range-native-2kp334uo/production -lSaytileKit -lc++ \
  -module-cache-path /private/tmp/saytile-owned-range-native-2kp334uo/clang-cache \
  tests/fixtures/AXFixtureActivationAudit.swift tests/fixtures/OwnedRangeNativeProbe.swift \
  -o /private/tmp/saytile-owned-range-native-2kp334uo/OwnedRangeNativeProbe-final
```

An earlier build attempt at `/private/tmp/saytile-owned-range-native-5fe9enyg`
compiled the native fixture but SwiftPM could not execute its manifest:
`sandbox-exec: sandbox_apply: Operation not permitted`. The final runner builds
production sources directly. No sandbox-disable flag or permission bypass was
introduced. The later full compilation succeeded; that does not replace AX
acceptance. No concrete production bug was established and no production file
or shared native test file was edited.

Entry branch: `test/owned-range-native-20261107`; entry HEAD:
`d361f1eaa915af15eaaf4097912bcc878afe29a7`, a descendant of requested base `c4c74e6`.
Read-only remote preflight found PR #6 open with no check rollup, remote integration
head `875f66fef52c10eac0e927512c9bb726f43d8e4c` and main
`a352a1c812c33388a1a908f21ecde30da80ad1cd` at observation time. No remote state was
changed, and no CI was awaited.

Next step belongs to parent integration: cherry-pick this dedicated test commit,
then run `python3 scripts/test-owned-range-native.py --execution-context unsandboxed`
once at the final integrated HEAD. Existing AX access is required; if unavailable,
retain BLOCKED. Only the final `OWNED_RANGE_NATIVE_PASS` marker **and** zero process
exit with `summary.json` native status PASS constitute a completed native run.
