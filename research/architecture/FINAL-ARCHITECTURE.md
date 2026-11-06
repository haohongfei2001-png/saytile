# Saytile 最终架构：双语言专家 + 单一 GPT-6 实时融合

更新：2026-11-07。**本文件覆盖 PR #5 旧版“多语言主模型 + 按需专家”的冲突决策。**

## 1. 正式产品决定

Saytile V1 默认由两个平等实时 ASR 专家和唯一 GPT-6 AI 核心组成：
- 中文专家：完整音频流。
- 英文专家：同一份完整音频流。
- GPT-6 Astra：持续接收两路 ASR 的增量候选，负责统一证据判断、融合和纠错。

两个 ASR 不按语言裁剪音频，不按整句语言路由，也不被限制为只输出单一语言。用户不选模型、不选语言、不看候选。用户界面只有一份持续更新的 transcript。

第三个 ASR 仅作为可选挑战者，Soniox v6 是优先候选；只有同音频测量证明有净收益才默认启用。模型数量、公开榜单和理论互补不构成收益证据。

## 2. GPT-6 API 能力裁决（官方文档核实：2026-11-07）

| 能力 | GPT-6 Astra (`gpt-6-astra`) |
|---|---|
| API 可用 | 是，Responses API |
| 文本输入/输出 | 是 |
| 流式文本输出 | 是 |
| 原生音频输入 | **否，模型目录标注 Audio not supported** |
| 实时音频流输入 | **否，不能把 Realtime endpoint 列表误读成该模型支持音频** |
| 直接听音纠错 | 否；没有真实音频输入，不得宣称 GPT-6 Astra 听过原音 |
| 上下文窗口 | 官方模型页 1,050,000 tokens |
| 最大输出 | 官方模型页 128,000 tokens |

GPT-6 Astra 可通过 Responses API 的 `stream: true` 输出文本事件；Saytile 将候选变化按短窗口合并后请求一次结构化 evidence selection。它只选择候选来源的 UTF-16 spans / unresolved，不自由生成转写文字。新证据覆盖范围变化时，允许新一轮请求；旧响应若候选版本已过期则丢弃。

OpenAI 当前有独立语音模型：
- `gpt-live-transcribe`：低延迟实时转写，支持音频输入和 transcript deltas。
- `gpt-transcribe`：高准确率文件转写，也可用于已提交的 Realtime turns。
- `gpt-realtime-2.1` / `gpt-live-1`：音频输入输出的实时语音模型。

这些不是 GPT-6 Astra。它们如被加入，只能作为独立 ASR/音频证据候选，不能冒称“GPT-6 原生音频”。本轮 F 配置（GPT-6 Astra 直接听音）判定 **NOT AVAILABLE / NOT RUN**。

官方来源：
- https://developers.openai.com/api/docs/models/gpt-6-astra
- https://developers.openai.com/api/docs/guides/latest-model
- https://developers.openai.com/api/docs/guides/realtime-transcription
- https://developers.openai.com/api/docs/models/gpt-live-transcribe
- https://developers.openai.com/api/docs/models/gpt-transcribe
- https://developers.openai.com/api/docs/models/gpt-realtime-2.1

ChatGPT Pro 订阅与 API 平台分别计费；Pro 不包含可任意用于 Saytile 的 API 请求额度。API 使用需独立组织、Key 和账单。官方说明：https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform

## 3. A/B 两个专家平等，不预设主模型

推荐初始工程基线（不是准确率冠军声明）：
- 中文：Qwen Audio 3.1 Message。
- 英文：AssemblyAI Universal 3.6 Pro。
- GPT 核心：GPT-6 Astra。

Qwen、AssemblyAI、Meta Muse、Soniox v6、SeedASR、GPT-Live-Transcribe 等进入可替换对照。Qwen 与 Assembly 的“中文/英文专家”是质量职责，不是输入限制。每条完整音频从开始到结束发给两个专家。

## 4. SingleTranscriptEngine

SingleTranscriptEngine 是唯一融合与发布协调器，内部保留多份候选，但只向 Store 发布一份 transcript revision：

1. 接收同一录音 epoch/generation 的两个 ASR 增量候选。
2. 校验 sequence、source sample range、语言标签、时间覆盖和候选代次。
3. 维护每路最新候选及历史证据，不按网络到达顺序覆盖。
4. 按 280ms 合并窗口 coalesce 高频 partial 事件，避免每 token 调 GPT。
5. 每次新证据快照变化后，由唯一 GPT-6 Astra 进行结构化选择；只接受候选 ID + UTF-16 span，禁止无来源生成。
6. 本地验证所选 span、音频覆盖、字符边界、否定/数字/单位/重复等保护签名。
7. 只将一个 preview/stable revision 写入 Store；旧 GPT 请求在证据版本变化时作废。
8. 结束讲话后等待两个 ASR EOS/final，执行最后一轮 GPT-6 融合，完成或保留 unresolved 状态。
9. GPT 失败不停止录音，不把未确认候选自动派发；保留最可信的既有文字和原音，可恢复。

GPT 不负责语言润色。其指令严格限定为逐字转写证据选择；不翻译、不总结、不扩写、不消除口语重复。标点可作轻量处理，但不能改变词汇或语义。

## 5. 唯一用户文字流与外部输入

候选、模型名称、raw/final 多版本都留在内部数据库。用户界面只展示一份 transcript。Saytile 自己尚未派发的文字可以被后续 GPT 证据修正。

外部应用输入继续使用既有 UTF-16 ledger：已派发范围有明确所有权；目标变化立即暂停；用户修改过的文字不得被覆盖；不重发整段、不重复插入、不自动发送或回车。

## 6. 本地识别与原音恢复

Apple SpeechAnalyzer 作为统一 Candidate 来源，进入同一 recording/generation/Store。云端专家同时工作时，Apple 可按设备资源策略提供独立证据；不强制多个本地大模型常驻。

断网时 CaptureWorker 与 PCMJournal 不变，Apple 在支持的语言/资产条件下接管；不能识别的音频保留并排队。恢复后按 audio digest/generation 续识别。

长音频复核必须从 PCMJournal 读取真实 sample range。现有 12 MB fanout 临时缓冲不能继续作为最终音频读取路径；在 PCMJournal 读取接入完成前，不启用基于内存快照的全段复核。GPT-6 Astra 本身不支持音频，因此当前架构不需要 Gemini/Scribe 组成第二条 AI 复听链。

## 7. 明确不做

- 不设 ASR 主模型等级。
- 不配置多个 GPT/LLM 仲裁器。
- 不默认 Gemini、Scribe、Claude 等二次模型链。
- 不向用户显示多份转写稿或 Raw/Formatted 切换。
- 不润色、改写、总结或扩写。
- 不把 GPT-6 Astra 宣称为原生音频模型。
