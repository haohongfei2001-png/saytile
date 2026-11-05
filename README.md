# Saytile

**自然开口，随时取用。**

Saytile 是始终待命的个人 AI 语音输入与表达工作台：连续接收讲话，独立保存原音与文字，并让当前和历史表达以尽可能少的操作进入目标应用。

> 当前交付是 **V1 设计恢复、交互原型和可执行数据契约**，不是可安装的 macOS App。恢复来源、重建部分和真实验证边界均有记录。

## 从这里开始

- [打开交互原型源码](prototype/index.html)：下载后用浏览器打开；含七个主要场景及删除/增量输入演示。
- [V1 设计修订报告](docs/Saytile-V1-Design-Revision.pdf)：产品、技术、修订、验收与下一步。
- [交付状态](docs/00-DELIVERY-STATUS.md)：已完成、未完成与发布状态。
- [产品及三版本路线](docs/01-PRODUCT-AND-ROADMAP.md)。
- [架构与成熟方案复用](docs/02-V1-ARCHITECTURE.md)。
- [两项中断修订的正式契约](docs/03-REBUILT-REVIEW-CONTRACTS.md)。
- [验收清单](docs/04-ACCEPTANCE.md)与[工程接续](docs/05-IMPLEMENTATION-HANDOFF.md)。
- [来源与原件校验](docs/06-PROVENANCE.md)。

GitHub 文件预览不会执行 HTML。原型是完整单文件，不请求麦克风、不调用 ASR、不操作其他应用；只有“复制”会在浏览器允许时使用剪贴板。编辑、删除和设置只影响示例数据。

## 版本边界

| 版本 | 范围 | 当前处理 |
|---|---|---|
| V1 | 常驻收音、连续转写、音文历史、恢复、复制及跨应用插入 | 唯一设计和研发重点 |
| V2 | 共享工位的轻声/低音量识别 | 后续独立研究，不作为 V1 前置 |
| V3 | 个人词库、授权资料适应、文字输入法 | 第三版研究，不提前开发 |

不以“本地优先”作为产品最高原则。识别路线按质量、延迟、可靠性、功耗、隐私、成本和维护性决定。保存与识别分离，不等于强制所有识别都在本机。

## 验证

```sh
python3 scripts/verify.py
# 可选浏览器检查
python3 -m pip install -r tests/requirements.txt
python3 -m playwright install chromium
python3 scripts/verify.py --ui
```

本轮：原有合成故障实验 **10/10**；新增数据契约 **37/37**；DOM 交互 **48/48**；Swift 6 接口类型检查通过，Foundation UTF-16 边界 **6/6**。详见 `evidence/`。这些结果不代表真实麦克风、Apple Speech、中文质量、macOS 辅助功能、ALAC 或整机功耗已经验收。

## 目录

`archive/` 保留恢复原件，不修改历史证据；`contracts/` 是修订 SQL/Swift 契约；`model/` 是可运行的设计参考模型，而非生产实现；`prototype/` 是消费级界面演示；`tests/` 与 `evidence/` 负责可重复验证。
