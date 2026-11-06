# Saytile ASR 当前状态与接续入口

更新：2026-11-06。**旧的“唯一 Soniox、不默认双模型”结论已失效。** 以后续用户最高质量指令、[DECISION](DECISION.md) 与本轮实现为准。

## 已确定的架构

- 同 PCM 的中文/英文专家实时并行；可增加混说模型和其他已支持专家。
- 默认最高质量确认，提供快速输入；供应商 final 不等于 Saytile 可外发。
- 真实时间与 UTF-16 对齐，AI 只能引用候选，疑难内容进入原音复听。
- 逻辑录音与独立模型运行分离；SQLite schema 3 增量升级；外部输入账本继续只追加且不重复。
- BYOK 使用每服务、每模型独立 Keychain 项与授权；调用、失败、用量和明确费率估算可追踪。

## 工程位置

正式仓库 `haohongfei2001-png/saytile`，分支 `research/asr-quality-2026-11-06`，[PR #4](https://github.com/haohongfei2001-png/saytile/pull/4)。本轮已经修改真实 `Sources/` 与原生测试，不再是仅有研究的 PR。RC1 生产基线为 `a352a1c812c33388a1a908f21ecde30da80ad1cd`，没有在正式安装或私人数据库上试迁移。

准确的最终源码、测试和候选包身份统一记录于 [REVISION-2026-11-06.md](REVISION-2026-11-06.md)，不在多份文件重复维护易过期的通过数。

## 继续保留的既有证据

| 证据 | 边界 |
|---|---|
| 112 条真人 × Apple 固定中文、Apple 已知语言、本地 Qwen3-ASR-1.7B，共336条输出 | 已有本地对照，不是新云 API 或新模型版本分数。 |
| 12 条 Apple paced 回放 | 按100ms发送，绕过生产VAD；不代表真实麦克风或新云延迟。 |
| 3 个生产 VAD probe | 覆盖长音频强制边界和活动短尾；不是ASR质量评测。 |
| 134 条旧语料 manifest | 不扩建，不重新传WAV或下载权重。 |

原始证据位于 `results/` 与 `../asr-2026-11-06/`。Mac 现有真人音频仍在 `/Users/hhf/.codex/saytile-asr-research-20261106/audio/`。本轮隔离构建与验证位于 `/Users/hhf/.codex/saytile-multi-asr-20261106/`。

## 不得混淆的验收状态

无授权云服务凭据时，不进行收费请求、不自动开通账户。协议 fixture、协调器离线集成、Mac 构建和 CI 证明工程行为，不证明实际中文 CER、英文 WER、混说 MER 或四阶段实时准确率。真实云验收须用现有片段与授权的同一配置完成；代码中的定向回放和证据导出入口用于这一步，不要求重建排行榜。
