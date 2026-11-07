# 4df87ad4 · 已完成但视觉规则已替代的工程基线

本目录属于 `1.0.0-rc.2-no-api.5`、运行时 `4df87ad4dd7ff94da2027f0c978ca5c5cb1d7292`，不是最新 UI 的验收。391 原生函数 / 511 场景、97 AppModel、50 本机真实网络协议 case、实际隔离 AX、8 段 Apple 合成音频、原生窗口和安装升级均在该源码通过。本次1800.54秒长跑以保存的全部28,800,000帧与参考逐字节一致结束，0 差异，23/23 条件通过。RC1 及生产数据未被替换。

本机测试使用顶部控制行/四个日常状态；随后 PR6 的 `3da2c3f` 最新规范改为无顶栏、左下复制、右下语音胶囊、三个日常状态，VAD声音结束即回待命。旧截图只能作为实际测试过的历史证据。本候选不授予当前 V1 的 `NO_API_ENGINEERING_READY`，不宣称真实服务、准确率或正式发布。

[完整证据清单](delivery-manifest.json) · [实测包和本地路径](delivery-paths.json) · [原始失败的上一个检查点](../final-no-api5/HOLD.md) · [原生协议测试](protocol/README.md) · [完整波形](local/realtime-assessment.json)。
