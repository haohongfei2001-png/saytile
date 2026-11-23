# 0.23（571）— Qwen 体验改善，Draft / HOLD

2026-11-23。继续 [PR #54](https://github.com/haohongfei2001-png/saytile/pull/54)，父 PR #53。产品源码 `a1ac008de50855ae0c03f30128f5b1f74269d617`；其后提交只含测试、证据和文档。安装 0.20（533）、main 和个人资料不变。

**本轮实际改善：同一 Qwen tokenizer 等价加载更快，中文最终结果保持。四项体验问题尚未全部关闭，裁决仍是 HOLD。**

| 本轮问题 | 结果 |
|---|---|
| 首字 | PASS（局部改善）：同批 15 段 P50 2.242→1.630 s、P95 3.271→2.681 s，14/15 段变快；未证明恢复至历史 1.563 s |
| 临时修订 | NO-GO：试验能减少部分 ABA，但仍拖住带新文字的完整候选，没有进入产品；历史 1→9 原件保留 |
| 面板连续性 | 本次 16/16 原速窗口最终正确；18/18 受控状态最终恢复。1/252 快速中间采样 FAIL 保留，历史多秒停更根因 UNKNOWN |
| 直接输入 | 实际 AX 通过 EOS 插入、去重、前后文和零发送保护；partial 稳定范围仍为 0，目标应用须等 EOS；早派发启发式存在反例，未加入 |
| 准确率 | PASS：15 段 8.10%；420 段 8.53%；20 派生段 8.51%；全部 440 条文字及状态与 569 一致，五个旧空子段仍 failed |
| 原速长句 | 首字 2.696→1.463 s；仍有 2.214 s 内部可见新字间隔，EOS 延迟未改善 |
| 完整 CI | PENDING：等待本轮最终 head 的完整 Xcode、AppModel 与前台 CI；历史 CI 不代替本轮 |
| 签名 / 打包 / 隔离断网启动 | PASS：使用已测试的同一 App 二进制，无安装替换 |
| 公证 / Gatekeeper | NOT_RUN / BLOCKED：任务禁止公证；App、DMG 均被拒绝为 Unnotarized Developer ID，无绕过 |
| 麦克风 / 8 GB / 整机功耗 | NOT_RUN：保持合盖，不以公开 PCM 冒充本人讲话 |

[本轮完整验收](CLOSURE.md) · [架构与历史](ARCHITECTURE.md) · [候选说明](INSTALL.md) · [机器收据](../../../evidence/experience-023/closure/package.json)

唯一当前候选：`/Users/hhf/Documents/GitHub/saytile/dist/internal-0.23-571/Saytile-0.23-571-arm64.dmg`，64,551,729 bytes，SHA-256 `1bae2309ca0b1493c7111e6080c24b3b8f6a86a83066008b53c0ca2f3d42b720`。没有变更官网或 Sparkle。

本轮无需用户做工程测试或提供账户授权。剩余主要限制是实际产品能力，不是靠权限、CI 绿灯或重复回放就能消除的项目。保留 569 的原始报告和全部失败，禁止用本轮改善反向改写历史结果。
