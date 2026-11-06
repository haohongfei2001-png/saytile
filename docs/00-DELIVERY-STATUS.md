> 当前稳定版仍是 RC1；PR #6 正在完成无 API 产品交付，`3f49682c` 后正在修复补审发现的历史音频权限与内存问题，不合并生产、不替换安装。最新本轮证据见 [V1-DEV-STATUS](V1-DEV-STATUS.md)；下方是只读意义的历史交付记录。

> 当前为 V1 RC1，源码 `8906a9d`；最新状态见 [V1-DEV-STATUS.md](V1-DEV-STATUS.md)，验证边界见 [RC清单](V1-RC-ACCEPTANCE.md)。**以下是设计恢复阶段历史快照**，不是当前未完成事项；PR #1/#2 已合并。

# 交付状态 · 2026-11-06

## 已实际完成

- 从恢复包读取并保存原始报告、七场景 HTML 原型、SQL、Swift 接口、测试脚本和来源索引。
- 按已知截图约束重建两项未交付修订：音频独立删除；稳定前缀增量派发。
- 完成 `contracts/schema.sql`（设计 schema v2）、`Contracts.swift`、可运行 SQLite/文件参考模型及测试。
- 原型统一为 Saytile；区分删除原音/删除记录；保留修改历史；加明确确认和演示重置；加入重复 revision 与前缀改写场景。
- 识别设置不再强制本地路线。默认原音保留至手动删除，启用期限整理须确认。
- 完成产品、技术、验收与工程接续文档；保留原件哈希和差异来源。

## 实际测试

| 范围 | 结果 | 不代表什么 |
|---|---|---|
| 继承 PCM/SQLite 合成实验 | 10/10 | 不代表 APFS 掉电恢复 |
| 新增删除/派发/UTF-16 数据契约 | 37/37 | 不代表真正的 macOS 插入适配器 |
| Chromium DOM 交互 | 48/48 | 不代表 Safari 或原生 App |
| Swift 6 接口类型检查 | 通过 | 不代表实现了接口 |
| Swift Foundation Unicode 边界断言 | 8/8（含 macOS 修复） | 不代表 AX 实际输入 |

浏览器采用 `set_content` 注入实际 HTML，因为执行环境禁止 file/http 导航。localStorage 在测试中使用明确的内存替身验证序列化与恢复；真实数据库重开/删除恢复由 SQLite 测试覆盖。未把替身写成真实磁盘耐久测试。

## 尚未完成

- 真实 macOS 录音、中文 ASR、ALAC 压缩、外部输入、设备/休眠行为和能耗。
- 共享音频块中存活片段的生产级重写。当前参考模型采用保守延期清理，状态明确为未完成；不会误删其他记录。
- 原 Pro 最后一轮文件的原件级恢复。那轮所称 12 项新增和 33 项浏览器检查无法复核，本轮不沿用其计数。
## 远端发布与 CI（2026-11-06）

- 正式仓库：`haohongfei2001-png/saytile`；公开状态由用户明确授权。
- 已将完整 67 文件设计交付提交到 `recovery/v1-design-20261106`。
- [PR #1](https://github.com/haohongfei2001-png/saytile/pull/1) 已创建并保持开放，**尚未合并到 main**；main 的原始提交为 `090ecd14`。
- GitHub Actions：`swift-contracts` 与 `data-and-prototype` 已在修复 UTF-16 边界问题后双双通过。相关检查仅覆盖 Swift 契约、合成数据、浏览器原型，不代表原生 Mac App 验收。
- 本次在真实 macOS 修复了 Foundation 在 UTF-16 代理对位置上的转换差异，新增组合字符边界断言。根目录 SHA256 清单已同步更新。

`scripts/publish_to_github.sh` 是历史准备脚本，不要在已有 PR 上再次运行。新的工程接续应直接使用现有 PR 或基于最新 main 新开功能分支。
