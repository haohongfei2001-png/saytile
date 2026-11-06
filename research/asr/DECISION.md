# 双语言专家 + GPT-6 Astra：正式 ASR 架构裁决

更新：2026-11-07。本文覆盖旧版多专家/多 AI 复核的冲突默认值。

## 默认配置

- 中文专家：Qwen Audio 3.1 Message（基线候选）。
- 英文专家：AssemblyAI Universal 3.6 Pro（基线候选）。
- 唯一 AI 核心：GPT-6 Astra / `gpt-6-astra`，OpenAI Responses API。
- 可选第三 ASR：Soniox STT v6、Meta Muse、其他有实际流式协议的模型；默认关闭，需证明收益。

两个专家完整接收相同音频，不能先按语言切分。中文/英文命名只表示专家职责。两者都应保留完整语言输出能力。

## GPT-6 能力边界

GPT-6 Astra 支持文本输入、Responses API、流式文本输出和长上下文，但官方模型目录明确标注 Audio not supported。它不能直接接收 PCM/音频文件，也不能直接承担实时音频识别。它只能融合 ASR 已产生的候选。

OpenAI 独立音频模型包括 `gpt-live-transcribe`（实时转写）、`gpt-transcribe`（文件/已提交 turn 转写）、`gpt-realtime-2.1`（音频输入输出语音模型）。这些模型不是 GPT-6 Astra。除非作为单独 ASR 方案纳入对照，否则不启用。

ChatGPT Pro 与 API 平台独立计费；Pro 订阅不能直接当作 API Key/额度。

## GPT 增量策略

- 候选更新按 280ms 窗口合并，不逐 token 调用。
- 证据快照发生变化时发起唯一 GPT 请求。
- 请求用 Responses streaming，等待结构化完成事件。
- GPT 只返回候选 ID 与 UTF-16 spans / unresolved。
- 若新证据在请求期间到达，旧响应不得覆盖新版本；以候选 generation/version 重新核验。
- 讲话结束时两个专家完成 EOS 后，再做最后一轮 GPT 复核。

## 禁止项

无 Gemini/Scribe/Claude 默认链；无第二 GPT 仲裁器；无多份用户转写稿；不润色、不改写、不总结、不扩写；GPT 未听音时不得宣称音频复听。

## 官方来源

- https://developers.openai.com/api/docs/models/gpt-6-astra
- https://developers.openai.com/api/docs/guides/latest-model
- https://developers.openai.com/api/docs/guides/realtime-transcription
- https://developers.openai.com/api/docs/models/gpt-live-transcribe
- https://developers.openai.com/api/docs/models/gpt-transcribe
- https://developers.openai.com/api/docs/models/gpt-realtime-2.1
- https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform
