# 双专家 + GPT-6 BYOK 与质量验收

## 用户需要配置的云服务

V1 默认只需要三项服务：
1. 中文实时 ASR Key（当前 Qwen Message）。
2. 英文实时 ASR Key（当前 AssemblyAI）。
3. OpenAI API Key（GPT-6 Astra 文本融合）。

每个 Key 单独保存在 macOS Keychain；不得写入 UserDefaults、SQLite、日志或源码。语音上传与候选文本处理分别明确授权。GPT-6 Astra 接收 ASR 候选文本和必要上下文，不接收原音。

Soniox v6 / Meta 作为可选第三 ASR challenger；未证明收益前关闭。Gemini audioReview、ElevenLabs Scribe finalASR 不再作为默认服务，也不应要求用户为默认 V1 配置这些 Key。

## API 能力与订阅

- `gpt-6-astra`：Responses API 文本模型，支持流式响应，不支持 Audio input。
- `gpt-live-transcribe`：独立实时语音转写模型。
- `gpt-transcribe`：独立文件/已提交音频转写模型。
- `gpt-realtime-2.1`：独立音频输入输出模型。
- ChatGPT Pro 订阅与 API 平台分别计费；Pro 不自动提供可用于 Saytile 的 API Key 或 API 额度。

## A-F 对照

A 中文专家 + GPT-6；B 英文专家 + GPT-6；C 双专家 + GPT-6；D Soniox v6 + GPT-6；E 双专家 + Soniox v6 + GPT-6；F GPT-6 Astra 原生音频 + ASR。F 官方能力不支持，标记 NOT AVAILABLE。

首轮 24 条同音频配对，必要时扩展至 112 条。复用已有 336 条 Apple/Qwen 结果，不下载大语料、不上传私人录音到未授权服务。

指标：CER/WER/MER、技术术语、数字/金额/时间/否定、首次可见延迟、讲话中修正收益、EOS 后修正延迟、GPT 新错误率、最终派发正确率。按中文/英文/混说分层。

## 授权与费用

不擅自开新账户、不购买订阅。真实云调用只在 Key、服务权限、音频/文本处理授权和费用授权均具备后运行。记录 request ID、音频秒数、token 用量和真实/估算费用；未知不记为零。
