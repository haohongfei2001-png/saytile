# Saytile SingleTranscriptEngine 状态

更新：2026-11-07。工程分支基于 PR #4 最新 HEAD `45af67049ddee2553fe1929a812aecb83cc157e4` 重建，尚未合并生产 main。

## 已完成源码改造

- 默认配置为中文 Qwen + 英文 AssemblyAI + 唯一 GPT-6 Astra。
- Soniox v6 / Meta 关闭为可选 challenger。
- 配置校验强制一个 GPT 核心，最多三路 ASR，拒绝默认 Gemini/Scribe 二级链。
- 引入 `SingleTranscriptEngine` actor，旧协调器名称仅留内部兼容别名。
- GPT 候选评审按 280ms coalescing，Responses API 改为 SSE streaming 并只消费 response.completed 的结构化结果。
- 设置界面移除“快速/最高质量”模式切换，文案强调唯一忠实文字流。

## 未完成

- CI / Swift 6 编译与原生回归尚待本分支运行。
- 没有云 Key/授权，本轮未发起任何收费模型请求。
- 24 条同音频对照未运行。
- Apple SpeechAnalyzer 统一 Candidate ingress 未实现。
- PCMJournal 任意 sample range 读取尚未接入音频复核；当前不启用额外音频复听模型。
- 真实外部输入的动态修正验收未完成。


Validation gate: CI for the synchronized PR #5 head is pending; do not treat source edits as compiled or tests as passed until the PR checks complete.
