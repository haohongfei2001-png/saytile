# ASR 研究阶段检查点 — 2026-11-06

生产基线 a352a1c，RC1 未修改；研究分支 research/asr-quality-2026-11-06，PR #4。

用户最新方向已取消扩展公共横评。已保存：112 条真人 × 3 配置共 336 条直接结果；12 条 Apple paced 回放；生产源码审计；Mac 三次 VoiceSegmenter probe（原片段、79 秒跨两次强制边界、活动尾部），三例均无样本遗漏或重叠。Whisper 主动停止于 55 条。原音与权重均未提交。

证据见 results/README.md、results/LOCAL_EVIDENCE.md、results/vad-probes/README.md 与 PRODUCTION_AUDIT.md。最新官方接口与公开证据层级见 VENDORS.md。没有云服务密钥或云调用，不把这些本地结果冒充云端成绩。

已收敛的选型为 Soniox stt-rt-v6 单实时引擎，Apple 保留离线备用，不默认二次定稿。DECISION 与 Codex IMPLEMENTATION 完整说明正在完成最后一致性检查，将在下一阶段提交；不得因此提前替换 RC1。
