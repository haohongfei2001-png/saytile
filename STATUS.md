# Current engineering work

The independent 0.22 performance investigation is closed as **NO-GO / Draft / HOLD**. No optimization showed repeatable benefit; both experiments were reverted.

Product: 0.22 (567), source `a90601b79e59333c97982e200dfb69e541c2bf95`. Accuracy retained: 15 real-time clips 8.10% CER, original 420 clips 8.53%; 440 texts/states identical. Final-source CI and isolated data-safety checks pass; these do not resolve the performance failure.

See [status](docs/delivery/performance-022/STATUS.md), [acceptance](docs/delivery/performance-022/ACCEPTANCE.md), [root-cause evidence](docs/delivery/performance-022/ROOT-CAUSE.md), [architecture](docs/delivery/performance-022/ARCHITECTURE.md) and [candidate instructions](docs/delivery/performance-022/INSTALL.md). Parent release evidence remains in [0.21 closure](docs/delivery/release-021/STATUS.md).

No merge, public release, notarization or replacement of the installed 533 took place. The signed diagnostic DMG remains unnotarized and Gatekeeper rejects it; do not promote or use it to replace the installed product.
