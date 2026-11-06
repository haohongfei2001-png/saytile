# Swift 6.3.3 compiler compatibility

2026-11-07 (Asia/Shanghai). PR4 source `0b1f61a`, native CI run `42265587630`, job `128056527891` failed during compilation, before runtime tests. The preserved excerpt is `ci-0b1f61-compiler-failure.log`.

The runner reports Swift6.3.3 (`swiftlang-6.3.3.1.3`). IR generation for `RecognitionSettingsView.swift` aborts with `SmallVector unable to grow` and requested capacity4294967297. Its reported function is the `CloudProvider`/optional-Actor reabstraction thunk `@$s10SaytileKit13CloudProviderOScA_pSgIeAghyg_ACIeAghn_TR`. This is compiler process failure (signal6), not a failed Saytile test or model request.

The provider Picker was passing the actor-isolated instance method `selectProvider` directly as the Binding setter. The minimal compatibility change replaces that function reference with the explicit closure `{ provider in selectProvider(provider) }`, matching the existing inline closures for other enum settings. This avoids converting the isolated enum-taking method value into the setter callback. It changes no provider choice, key handling, consent reset, user setting, automatic-recovery restriction or child accessibility identifier. Root's separate removal of the ancestor DisclosureGroup AX identifier is preserved.

Validation performed here: `swift build --scratch-path /tmp/saytile-rc2-pipeline --product Saytile` succeeds on installed Swift6.4; log `compiler-compatibility-local-build.log`. `git diff --check` passes. No full tests were rerun by this reviewer and no visible application/window was opened.

**Swift6.3.3 resolution remains subject to the next authoritative CI build.** The stack trace identifies the relevant thunk and motivates this workaround; the local6.4 build alone does not prove the older compiler is fixed. Root owns the source checkpoint and next CI verification. No compiler pin, CI downgrade, validation bypass or toolchain installation was introduced.

Runtime 8f2d71b CI run42269235645 subsequently completed successfully, including native tests, AppModel, release build, both CLI guards, rendering and startup. The prior Swift6.3.3 IRGen crash is resolved on the actual CI runner. See ci-runtime-receipt.json; cloud connectivity remains untested.
