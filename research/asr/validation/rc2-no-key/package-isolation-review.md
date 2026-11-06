# Candidate identity and isolated packaged processes

Review began at `a602236ea48f7140b57c46e916bae4c5d43f5cd9`. Source changes and final package tests are committed/coordinated by the root agent. No installed App, real database, microphone, system permission or private preferences were inspected or modified in this review.

## Corrections

- A normal process given only `--data-directory` previously used `UserDefaults.standard`. Consequently, earlier held-process duplicate-instance/idle evidence proved isolated **database paths**, but did not prove isolated preferences; those historical results must not be retroactively described as fully isolated. The revised `AppDelegate` creates its private random preferences suite for every explicit data directory, defaults to cloud off and automatic recovery off, and sets the process-only argument domain to `hasLaunched=true` and `shortcutChoice=disabled`. The first-run decision now uses the selected preferences. This also prevents command-line defaults from re-enabling the first-run panel or shortcut in these isolated processes. Normal production launch without an explicit directory retains standard preferences.
- A normal isolated launch emits one receipt derived from actual applied configuration, shortcut, panel visibility and hotkey registration. The held candidate in `test-install-upgrade.py` and the process in `test-app-idle.py` must produce the fully isolated receipt. This is not a new CLI mode or a substitute for cloud/recording acceptance.
- Both package tests now require explicit `--expected-source`, `--expected-version` and `--expected-binary-sha256`, and reject mismatches/dirty sources before executing the candidate. Upgrade evidence records the copied candidate's binary hash as well as candidate and previous DMG hashes and previous binary hash. Root final UI/CLI evidence must reference this same DMG-derived executable hash, not an independently built App.
- The 10-second idle boundary no longer calls `min/max` on an empty post-warmup sample set: warm RSS is `null` when no sample is at least 10 seconds old. Such a short measurement cannot claim a steady-state resource result.

## Verification actually run

`isolated-launch-and-identity.json` / `.log`: **6 checks PASS**. Two are actual normal launches of the new development App with owned empty data directories, held for one second then intentionally SIGTERM'd. Both report cloud/recovery off, disabled shortcut, no visible panel and no registered hotkey. The second also passes conflicting `-hasLaunched NO -shortcutChoice option-space` arguments. These receipts do not claim that all other applications kept their foreground status; no unrelated UI was queried.

The other four checks invoke the actual idle script against synthetic bundle metadata with wrong source, wrong version, wrong executable hash or dirty-source flag. All are rejected before launch. The fake executable is never run. Python compilation and `git diff --check` pass.

The actual development App is deliberately reported as **dirty**, source metadata `a602236`, release label `1.0.0-rc.2-candidate.2`, executable SHA256 `9689718662c46bf8f34ddd10b498157c266c6d252bb7ef49090383ee71c89dfb`. Its successful build and these checks are not final clean-package acceptance. No true system permission prompt or private production preference values were tested.

Reproduction from the repository root (owned build and temporary fixtures only; the six checks below are the same checks used for the saved evidence, with output printed instead of overwriting historical logs):

```sh
SAYTILE_BUILD_SCRATCH=/tmp/saytile-isolated-launch-build \
SAYTILE_APP_OUTPUT=/tmp/saytile-isolated-launch/Saytile.app scripts/build-app.sh debug
python3 - <<'PY'
from pathlib import Path
import hashlib, plistlib, subprocess, tempfile, time
binary = Path('/tmp/saytile-isolated-launch/Saytile.app/Contents/MacOS/Saytile')
receipt = 'SAYTILE_ISOLATED_LAUNCH cloud_enabled=false automatic_recovery=false shortcut=disabled visible_panel=false hotkey_registered=false'
with tempfile.TemporaryDirectory(prefix='saytile-isolated-launch-test-') as tmp:
    base = Path(tmp)
    for name, extra in [('explicit_directory_only', []), ('conflicting_argument_preferences', ['-hasLaunched', 'NO', '-shortcutChoice', 'option-space'])]:
        process = subprocess.Popen([str(binary), '--data-directory', str(base/name), *extra], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            time.sleep(1)
            assert process.poll() is None, name
        finally:
            process.terminate()
            out, err = process.communicate(timeout=10)
        assert receipt in out, (name, out, err)
        assert (base/name/'Saytile.sqlite').is_file()
        print('PASS', name, receipt)
    fake = base/'Identity.app'
    (fake/'Contents/MacOS').mkdir(parents=True)
    executable = fake/'Contents/MacOS/Saytile'
    executable.write_text('#!/bin/sh\nexit 99\n')
    executable.chmod(0o700)
    good = {'SaytileSourceRevision': 'a'*40, 'SaytileReleaseVersion': 'identity-fixture', 'SaytileSourceDirty': False}
    digest = hashlib.sha256(executable.read_bytes()).hexdigest()
    cases = [('wrong_source', {'SaytileSourceRevision': 'b'*40}, 'source does not match'),
             ('wrong_version', {'SaytileReleaseVersion': 'wrong'}, 'release does not match'),
             ('wrong_binary', {}, 'binary does not match'),
             ('dirty_source', {'SaytileSourceDirty': True}, 'uncommitted runtime sources')]
    for name, override, expected in cases:
        with (fake/'Contents/Info.plist').open('wb') as stream:
            plistlib.dump(good | override, stream)
        result = subprocess.run(['python3', 'scripts/test-app-idle.py', '--app', str(fake), '--seconds', '10',
                                 '--expected-source', 'a'*40, '--expected-version', 'identity-fixture',
                                 '--expected-binary-sha256', '0'*64 if name == 'wrong_binary' else digest,
                                 '--output', str(base/(name+'.json'))], capture_output=True, text=True, timeout=5)
        assert result.returncode != 0 and expected in result.stderr, (name, result.stdout, result.stderr)
        assert not (base/(name+'.json')).exists()
        print('PASS_REJECTED_BEFORE_LAUNCH', name)
PY
```

## Final package commands and rollback boundaries

After the final runtime commit, package once. Mount the intended DMG readonly, verify strict signature, and obtain its exact metadata and executable hash. Use those values for both scripts:

```sh
python3 scripts/test-install-upgrade.py --dmg "$RC2_DMG" --previous-dmg "$RC1_DMG" \
  --baseline-ref v1.0.0-rc.1 --expected-source "$RC2_SOURCE" \
  --expected-version 1.0.0-rc.2-candidate.2 --expected-binary-sha256 "$RC2_BINARY_SHA256" \
  --output research/asr/validation/rc2-no-key/install-upgrade-final.json
python3 scripts/test-app-idle.py --app "$RC2_APP_COPIED_FROM_DMG" --seconds 120 \
  --expected-source "$RC2_SOURCE" --expected-version 1.0.0-rc.2-candidate.2 \
  --expected-binary-sha256 "$RC2_BINARY_SHA256" \
  --output research/asr/validation/rc2-no-key/app-idle-final.json
```

The upgrade script retains the stopped pre-upgrade complete data copy and checks that RC1 rejects schema 3 without changing it. Rollback opens a separate restored copy with the actual RC1 App and preserves the upgraded directory. It does not implement in-place downgrade or automatic recovery of content created only after upgrade. The RC1 app embedded source is historically `8906a9d`, while the release tag is `a352a1c`; the scoped runtime diff is empty, so these metadata SHA values must not be assumed equal. Known actual artifact/binary hashes and release metadata anchor the released baseline.

Root's revised `docs/V1-INSTALL.md` now correctly identifies candidate.2, says not to replace RC1 now, requires a stopped full-directory backup for any future upgrade, and describes schema-3 refusal and explicit snapshot rollback. This removes the previous RC1 installation wording embedded in the candidate DMG. The final candidate package/UI/upgrade/idle tests remain for the root agent; this review did not install or overwrite RC1.
