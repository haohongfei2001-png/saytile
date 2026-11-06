# Saytile ASR 决策交付

本目录的入口是 [最终技术裁决](DECISION.md) 和 [Codex 实施要求](IMPLEMENTATION.md)。唯一主方案为 Soniox `stt-rt-v6` 单实时引擎，Apple 保留本地备用，不默认双模型。

- [状态与接续说明](STATUS.md)
- [供应商、当前接口与证据层级](VENDORS.md)
- [生产 VAD / 切段 / 版本协调审计](PRODUCTION_AUDIT.md)
- [已完成结果与语料归属](results/README.md)

研究 PR 保留已有实验，新增的实际检查仅限三个生产切段边界。它不实现生产云端替换，也不继续建设公共 ASR 评测平台。RC1 保持原状。
