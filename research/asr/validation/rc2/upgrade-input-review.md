# RC2 upgrade, rollback and input-path review

2026-11-07, parent checkpoint `1caa46b6`. This review used synthetic SQLite/audio fixtures, tagged public source, temporary app copies and simulated input access only. It never inspected or changed the production Saytile database, recorded microphone audio, wrote into another user's application, queried credentials or called a cloud model.

## Findings and changes

1. Existing upgrade validation was stale. `test-rc-storage-processes.py` tried compiling only four Swift files, which no longer satisfy PR4's model/fusion dependencies; actual pre-fix compiler failure is retained in `storage-processes-before.log`. Both `StoreProcessProbe` and packaged installation checks still asserted schema2, while the product is schema3. These scripts could not substantiate an RC2 upgrade.
2. Repaired the existing process test to link the current Swift package, compile actual tagged Beta/RC1 storage writers, and compare every preexisting table plus audio hashes across schema1/2→3. The package probe uses `@testable import` only behind `SAYTILE_PACKAGE_PROBE`; released source probes continue compiling without that flag. Existing SIGKILL, write-failure, intent-resume and uncertain-dispatch assertions remain.
3. Updated the packaged-app test to accept `--previous-dmg` (old `--beta-dmg` remains compatible), validate the previous release identity, test RC1→schema3, and test real RC1 refusal of the newer database. Explicit rollback restores a stopped pre-upgrade copy into a different disposable directory; the upgraded copy remains intact. Nothing lowers `user_version`, drops new tables, silently restores an older database or claims a one-click in-place downgrade.
4. Added `SaytileStore.activeRecognitionPhases(recordingIDs:)` for production UI status requested by the parent/pipeline agent. It queries only the record's active generation, matching audio epoch, running fusion session and running model attempt. Final ASR takes precedence over acoustic review, text arbitration and streaming. Deduplicated IDs are processed in bounded batches of500, not one query per row. No secrets are read; configured-but-idle services do not become fake activity.
5. Read through Store reservation/evidence checks and NativeInputCoordinator/AX dispatch. No new production input defect found. Added combined production Store fusion→NativeInputCoordinator regression tests because those layers were previously mostly checked separately: exact UTF-16 suffix once with Chinese/numbers/units/emoji; duplicate result no retry; failed expert makes stale publication produce zero external attempts while a later independent utterance can still proceed. Only the OS access object is simulated; this is **not** real AX/cloud evidence.

## Executed evidence

- `upgrade-input-native.log`: **58 tests / 6 suites PASS**, including two new phase-state tests and two new combined fusion/input tests. Covers stale generations, restart, completed/failed review removal, >500 requested IDs, existing Store path/migration and input identity/non-replay regressions. The first integration build encountered the parent's temporarily missing `AppModel.recognitionPhaseLabel`; rerun after that method landed passed. That temporary build mismatch is not presented as a released-product failure.
- `storage-processes.json` / `.log`: **12 checks PASS**. Actual tagged Beta and RC1 writers preserve all existing tables/audio through schema3; RC1 refuses schema3 without changing content; explicit old-copy restoration works; real SIGKILL and kernel write-limit failure preserve atomicity, text, draft and uncertain-delivery boundaries. The report records the compiled probe SHA256 and development source-dirty state. No claim that development-source checks equal final packaged candidate validation.
- `install-upgrade-preview.json` / `.log`: **8 packaged checks PASS**, actual released RC1 app source `8906a9d`, metadata/tag source `a352a1c`, upgraded to existing clean preview runtime `76e89c2`. Read-only DMG verification, ad-hoc signatures, isolated installation, original audio/version/draft/dispatch preservation, safe old-app refusal, explicit backup-copy restoration, three restarts, duplicate-process rejection and forced-exit recovery passed. This proves the migration path against that preview; it does **not** claim the newly edited RC2 runtime was packaged/tested.
- `git diff --check` and Python syntax compilation passed.

## Final candidate command and boundary

Parent must rerun the same existing script against the final clean candidate DMG after commit:

```sh
python3 scripts/test-install-upgrade.py \
  --dmg /ABSOLUTE/FINAL-CANDIDATE.dmg \
  --previous-dmg /Users/hhf/Documents/GitHub/saytile/dist/Saytile-1.0.0-rc.1-arm64.dmg \
  --output research/asr/validation/rc2/install-upgrade-final.json
```

RC1 deliberately cannot open schema3. A rollback requires a complete pre-upgrade directory copy made with Saytile stopped; retain the upgraded directory separately so any newer text/audio is not discarded. This test does not implement automatic backup retention or merge post-upgrade data into the older schema. Actual production installation remains withheld by the parent until RC2 delivery conditions are met. Final packaged validation, real isolated AX interaction and real cloud connectivity are separately attributable work; the synthetic counts above cannot replace them.
