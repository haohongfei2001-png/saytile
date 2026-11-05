# V1 验证记录

## 2026-11-06 · 基线

- PR #1：远端 data-and-prototype / swift-contracts 全部 SUCCESS。
- 本机 `python3 scripts/check_integrity.py`：66/66 文件一致。
- 本机 `python3 tests/test_recovery_contracts.py`：37/37 通过。
- 本机 Swift 6 契约 + SwiftSmoke：8/8 Unicode 断言通过。
- 环境：macOS 27.0 (26A428)，arm64，Swift 6.4，Command Line Tools SDK。

这些是继承设计契约验证，不代表原生 App 已可用。原生验证将在实际执行后补充。
