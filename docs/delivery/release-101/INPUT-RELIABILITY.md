# 1.0.1 输入确认定向复核

基线：`f3baa0a255931dbb16291690699790e3d54f8bde`，1.0.0（572）。独立分支 `codex/release-101-input`。
本报告范围仅为已有外部输入的读回确认，未打开浏览器、修改安装版本或访问用户资料。
当前改动及测试的逐文件 SHA-256、二进制 SHA-256 见 `evidence/release-101/input/receipt.json`；整合后的最终 Git SHA 与 CI 由发行主线另行绑定。

## 结论

**已修复一个可确定复现的产品缺口，但不能宣称历史 Safari 失败已彻底消除。**

原实现对 `settledWrite` 外层快照抛出的 `unsupported` 允许有限只读确认；同样错误发生于完整字段 witness 的前后两次快照时，却被 `try?` 折叠成 `nil`，立刻失效。是否能继续获得相同的完整证据取决于错误恰好落在哪一层调用，不符合已有有界确认规则。

新增内部 `checkedTextWitness`，只让写入后的 settlement 保留快照错误类型。原有 `textWitness` 仍然失败即不可用，所有写入前判断不变。只有既有的 `unsupported` 进入原有只读采样；可读但不同的目标、窗口、页面、光标、选区、完整字段和权限/敏感/归属错误继续拒绝。

- 总采样仍为最多 4 次，每次等待 220 ms；未增加次数、等待时间或 AX 写入超时。
- 任何读取缺口之后仍需两次新的完整字段证明，并要求期间无内容、焦点、选区或页面变化。
- 一次调用只有一次外部写入尝试；不重新聚焦、重发文字或自动发送。
- 不持久化目标字段内容；原有 owned range、UTF-16 边界与前后文保护不变。

## 历史 Safari 与 Chrome 证据

原件保持不变：`evidence/release-100/ci/e988-foreground/` 和 `e988-foreground-rerun/`。

Safari 首轮 `AXTextWriteTimeout` 用时 150 ms，实际写入一次且目标文字完全正确。四个自身内容通知均报告相同进程、应用、窗口、编辑器、页面和预期光标；之后外层快照出现两次 `unsupported`，再恢复可读，最终返回 `unverified`。日志没有记录每个内部 witness 的错误与时间，**无法确定是否也触发了本次修复的内部错误折叠**。原失败主要形状与“第一次采样期间自身通知到达、两次不可读、最后只剩一次完整采样”的有限预算耗尽一致。

新增 `safari-budget` 重放此观察顺序：旧版与新版均只写一次，最后仍为 `unverified`。这项安全拒绝是测试 PASS，而不是实际自动输入 PASS。不能用增加超时、重跑或减少证明次数抹掉历史 FAIL。历史同 HEAD rerun 通过也不证明以后不会再次暂时不可读。

Chrome 普通路径与焦点超时路径，在首轮和 rerun 原始日志中均首次插入 confirmed、追加 confirmed、写入计数 1→2，后续手工选区、编辑、取消、切换均使绑定失效。该批证据未复现 Chrome 追加异常；此次没有根据推测改动追加条件。

## 当前验证

| 项目 | 结果 | 范围 |
| --- | --- | --- |
| 真实 SaytileKit 直接 swiftc 编译 | PASS | 原生产源码，CLT，独立临时构建目录 |
| 同一故障注入探针，修复前 | FAIL | 可恢复的内部快照缺口提前 unverified，后续防护挑战未到达；原 JSON 保留 |
| 同一故障注入探针，修复后 | PASS 16/16 | 真实 coordinator + SQLite，操作系统边界为合成注入 |
| 短暂 witness 缺口恢复 | PASS | 两次新完整证明后 confirmed，约 0.787 秒；旧版约 0.360 秒提前拒绝 |
| 永久不可读、只有一次完整证明 | PASS 安全拒绝 | unverified，绑定失效，不重放 |
| 窗口、编辑器、页面、光标、选区、前后文变化 | PASS 安全拒绝 | 相同字段前后完整性条件未降低 |
| 页面不完整、内容/焦点/布局事件、取消 | PASS 安全拒绝 | 已写的一次尝试不重放，不取得后续修改所有权 |
| 历史 Safari 采样预算形状 | PASS 安全拒绝 | 自动确认仍未通过，不冒称根治历史兼容性限制 |
| 前台浏览器 fixture 编译 | PASS | 包含新的 witness 诊断转发；未运行浏览器 |
| 新 Swift Testing 用例语法解析 | PASS | 仅语法解析，不是测试运行 |
| 完整 Swift Testing | BLOCKED 本机 / 待 CI | 首次命令因 nested sandbox 失败；仅有 CLT，不反复排错、不跳过测试 |
| 最终 SHA 原生 AppKit/WK/Chrome/Edge/Safari | NOT_RUN | 由主负责人在同一整合 SHA 上统一 CI 验收 |

原始机器结果：`evidence/release-101/input/before.json`、`after.json`。修复前 16 场景中只有预算耗尽安全拒绝场景通过；其余场景的 post-gap challenge 未到达，并不表示存在 15 个错投缺陷。修复后所有后续挑战均实际执行。每场景都检查重复调用不重放，且实际写入尝试数为 1。

新增 Swift Testing 覆盖同一 15 场景、历史预算耗尽形状以及 AX witness 错误类型保留。未删除或削弱原有断言。未把确定性操作系统替身当作真实 AX/浏览器验收。

## 重放与整合

`tests/fixtures/InputWitnessSettlementProbe.swift` 使用 `@testable import SaytileKit`，可按现有 `scripts/test-owned-range-native.py` 的直接编译流程链接真实生产静态库。先编译基线库，再编译修改后库，使用相同探针源码；`before-build.json` 和 `after-build.json` 保存实际编译源码清单，`receipt.json` 保存探针和二进制摘要。探针仅使用随机 `/tmp/saytile-witness-*` SQLite，完成后关闭并删除自身夹具。

整合后运行完整 Swift Testing，以及已有 foreground/owned-range CI，不修改现有门槛。如果 Safari 再次耗尽同一预算，继续记录 unverified 并保留失败证据；不能把此次有限读回改善包装成无条件自动输入成功。
