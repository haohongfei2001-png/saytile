# Independent diagnostic boundary review

Read-only review of `DiagnosticDirectory.swift`, `ConnectionSetup.swift`, the AppDelegate guards before AppModel construction, and `check-probe-isolation.py`. No application was launched, no production directory contents were inspected, no microphone or cloud service was used, and no runtime/test source or HEAD was changed by this reviewer.

## Findings corrected during review

1. The CLI checker originally protected production-path rejection cases with a Python `assert` that the binary contained the early-guard marker. `python -O` / `PYTHONOPTIMIZE` removed that protection and the result assertions, permitting an older unguarded executable to be invoked with the production path. A compile-only inspection of the original function confirmed that the marker vanished from its optimized bytecode; the module and subprocesses were not executed. The owner fixed `check()` to reject optimized mode with an ordinary `if`/exception before reading the binary, and made the two-marker old-candidate gate an ordinary `if`/exception. `checker-guards.log` records the owner's bounded checks: optimized mode and an old dummy candidate are refused with zero subprocess launches.
2. The application originally recognized only the separate `--data-directory value` spelling. A bare `--data-directory=value` without another diagnostic flag could fall through to normal startup and the default archive. The owner added an explicit exit-64 rejection at the very start of `applicationDidFinishLaunching`, before directory choice, preferences, AppModel or Store. The CLI checker now requires that new marker and tests this rejection. The supported separate-argument syntax is unchanged.

Both corrections are present in the reviewed final code. No remaining concrete P0/P1 issue or normal-temporary-directory compatibility defect was identified in this bounded review.

## Boundary reasoning

- The lexical check runs first, rejecting the default production root and all descendants, with standardized path components and conservative case/canonical-Unicode equivalence. Those direct cases are rejected before inspecting production-path metadata.
- Canonical validation resolves the nearest existing ancestor with `realpath` and appends only the missing standardized suffix. It therefore detects aliases in a parent chain even when the requested leaf does not yet exist. Dangling symlinks, cycles, non-directory ancestors and unexpected filesystem errors fail closed. Validation itself creates or enumerates no directory and opens no archive.
- An independent path under a standard parent alias such as `/tmp` remains permitted. A leaf symlink is still rejected separately. The Store also standardizes its root before opening it, so the guard and the subsequent Store use consistent lexical normalization.
- Connection setup calls the boundary guard before checking whether its candidate directory is empty. Its output must be a JSON file directly inside that isolated directory, and existing data / leaf aliases are refused. Export remains configuration-only, checks consent/applied state/credential presence, and does not overwrite an existing completed output or export credential values.
- AppDelegate executes the path guard before creating the isolated preference suite or AppModel. Diagnostic or explicit-directory launches still use their own preference suite, automatic recovery off, shortcut disabled and optional floating entry disabled. An ordinary launch with no diagnostic/explicit-directory option retains the intended normal product behavior.
- The checker refuses unsupported Python optimization and old candidate binaries before any candidate process starts. Its production-path tests rely on the reviewed early rejection path; it does not read the user's database afterwards to infer that nothing changed. The sole normal Store path in this check uses an owned temporary directory, an explicitly cloud-disabled configuration and an absent synthetic input, with zero imported recordings/model runs required.

## Evidence and remaining execution scope

The separate owner-run directory/setup unit regression covers production lexical forms, parent aliases, missing suffixes, dangling/cyclic aliases, files/invalid URLs and safe independent paths. This review does not add another unit-test count. The previously pending **17-case preview App CLI run now has a passing receipt in `actual-cli.json`**: all production/alias/malformed-directory cases reject before Store construction, and the isolated cloud-disabled case creates zero recordings/model runs. The separate `setup-cli.json` reports seven setup rejection checks against the packaged preview candidate (`538e2d8`, dirty-source preview). These are preview receipts, not the future frozen no-api.5 results; the coordinated frozen candidate will be verified separately. No endurance test was repeated.

At the no-api.5 preparation follow-up, all four reviewed files still have exactly the hashes below. The optimized-Python rejection and equals-syntax rejection remain before any relevant unsafe operation. No new concrete safety or normal-temporary-path compatibility issue was found, and no App/test process was launched by this follow-up review. The completed 1067f1ad 30-minute engineering baseline is retained unchanged; the requested new-version validation remains unstarted until its new freeze and subsequent explicit long-run start message.

Reviewed file SHA-256 values:

| File | SHA-256 |
| --- | --- |
| `Sources/SaytileKit/DiagnosticDirectory.swift` | `e85e5b04495b825c05739f16648c71a5a53950420294cfa6907a17b93193292a` |
| `Sources/SaytileKit/ConnectionSetup.swift` | `f63236e4e521630c22b5efda5c7ca42993797c15e8cbbd7adb869c08f7ac7cc0` |
| `Sources/SaytileApp/SaytileApp.swift` | `afc4bac104ec010f9ac6dd619ead25b6fade36247620ca73e02218fd7cad065b` |
| `research/asr/validation/fusion-quality/check-probe-isolation.py` | `2627a822b9cafabf6c99cf7ecd1f6b9df949c9c992fbd8026dcdcfc52151840d` |
