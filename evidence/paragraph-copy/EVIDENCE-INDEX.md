# Evidence provenance

All top-level package/native/CI/rollback/activation receipts bind product source `58bc8f96f79942881d1ae3221fd6219635833907`, 0.17 (488). Documentation/evidence is committed independently of that signed source.

- [Final delivery](DELIVERY.md) and [machine receipt](machine.json).
- [Final CI](ci/summary.json) is the collector output preserved unchanged; its manifest verifies that original collection. Historical `/private/tmp/` evidence paths in that collector map to [failed 8ffa CI](ci-failed-8ffa4461/) and [e440 diagnostic CI](attempts/e4407fd3/ci/).
- [Regression provenance](regression/provenance.json) distinguishes pre-final targeted tests from final full CI.
- `attempts/` and `ci-failed-8ffa4461/` preserve earlier outcomes, not current installation state. `packaging-scope.json` is a pre-install observation; [activation.json](activation.json) supplies the final installation result.
- No user audio/database/clipboard/Keychain test reads. Local image captures render synthetic data inside real AppKit views; CI artifacts originate from disposable runner fixtures.
