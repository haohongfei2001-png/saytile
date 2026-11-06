# Saytile 最终架构决策日志（2026-11-07）

## ADR-001 — 两个平等 ASR 专家（取代主模型架构）

中文与英文专家地位相同，每条完整音频都接收同一 PCM 流。角色表示质量职责，不是语言限制。任何一方都不能被预设为主模型。

## ADR-002 — 唯一 GPT-6 Astra 核心

只允许一个文本融合模型：OpenAI Responses API 的 `gpt-6-astra`。它持续处理候选证据变化，输出候选 span 选择和 unresolved，不自由生成词汇。禁止多仲裁器投票。

## ADR-003 — GPT-6 Astra 不支持原生音频

截至 2026-11-07 官方模型目录标注 GPT-6 Astra Audio not supported。Responses streaming 是文本响应流，不等于实时音频流。GPT-Live-Transcribe、GPT-Transcribe、GPT-Realtime-2.1 是不同模型，只能作为独立 ASR/音频候选，不能冒称 GPT-6 Astra。

## ADR-004 — 单一 transcript

用户界面只显示一份持续修订的文字。候选和修订事件保留在内部用于审计、恢复和质量测量。Raw/Formatted/用户稿可在数据层区分，但不得向用户暴露多份稿件或要求选择。

## ADR-005 — 第三 ASR 需要边际收益

Soniox v6 可作为 D/E 方案挑战者；仅在同音频测试证明净准确率提升且延迟/可靠性代价可接受后启用。不能预设 Soniox 是主模型。

## ADR-006 — 采集、原音、识别、融合、输入解耦（保留）

PCMJournal 是音频事实源。网络或任一模型失败不能阻塞录音。所有模型只写 Candidate Store；SingleTranscriptEngine 是唯一正式 transcript publisher。

## ADR-007 — 外部输入账本不可退化（保留）

UTF-16 增量派发、目标绑定、用户修改保护、不自动发送、不自动回车继续有效。已经外部派发的文本不可被后台悄悄重写。

## ADR-008 — 订阅与 API 计费分离

ChatGPT Pro 不等于 API credits；API 账单独立。Saytile BYOK 仍需 API Key、API organization 权限与相应账单授权。
