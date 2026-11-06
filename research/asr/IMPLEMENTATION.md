# SingleTranscriptEngine 实现与接续规范

更新：2026-11-07。

## 唯一数据通路

`CaptureWorker → PCMJournal → 两路完整音频流 → Chinese/English ASR Candidates → SingleTranscriptEngine → GPT-6 Astra evidence selection → 唯一 transcript revision → UTF-16 direct-input ledger`

第三个 ASR 作为可选 challenger 加入相同候选流。Apple SpeechAnalyzer 也作为本地 Candidate 来源进入同一 recordingID/audioEpoch/generation，不拥有独立发布权。

## SingleTranscriptEngine 职责

- 为每个 recording/generation 维护每路最新候选和历史来源。
- 同一录音完整 PCM 广播给每个启用的 ASR。
- 对 provider sequence、source range、EOS、语言标签和迟到事件进行验证。
- 280ms 合并高频候选变化；不是每个 token 请求 GPT。
- 只有一个 GPT-6 Astra Responses 请求链；请求重叠时 coalesce，不并发启动多个相同快照。
- GPT 结构化结果只能引用已存候选及 UTF-16 范围。
- 本地校验数字、金额、时间、单位、否定、重复、术语和真实音频覆盖。
- 新证据代次变化后，旧 GPT 响应失效。
- EOS 后等待所有必要专家完成，执行最后一轮融合。
- 发布唯一 preview/stable/final transcript revision。

## GPT API 实现

Responses API 支持 `stream: true`。Saytile 应通过 SSE 接收 `response.completed`，使用最终结构化输出作为候选选择；不得将 GPT 文本流中尚未完成的 JSON 直接发布为正式转写。若只拿到 GPT 文本输出而没有原音输入，不得称为 acoustic review。

## 候选与正式稿边界

ASR adapter 只能返回自己的 ProviderTranscriptEvent。候选写入 Store 后由 SingleTranscriptEngine 处理。GPT 不能直接写正式 transcript、稳定前缀或外部 ledger。Store 再次验证 ticket、generation、候选身份和 Unicode 范围。

## 文字保护

Saytile 内部显示文本可在未派发范围内修正。外部应用中已拥有/派发的 UTF-16 范围不可自动覆盖；目标改变时停止派发；用户编辑过的内容受保护。不自动发送或回车。

## 当前实现边界

本轮核心引擎改造只完成单一 GPT 约束、双专家配置契约、coalesced GPT 更新与 Responses streaming 接收。Apple SpeechAnalyzer Candidate ingress、PCMJournal 任意范围读取、端到端云质量对照及外部真实文本修订仍需后续独立验收。不能把文档架构等同于这些能力全部完成。
