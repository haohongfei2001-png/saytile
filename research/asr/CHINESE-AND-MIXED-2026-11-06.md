# Saytile 中文专家与中英混说流式适配研究

核查日期：2026-11-06。用途：修订 PR #4 的质量目标，支撑多模型工程接入。此文把可核实的接口事实与尚未验证的识别质量结论分开；没有进行付费调用、重新下载模型或传输 WAV。

## 裁决

**中文专家首选接入候选：`qwen-audio-3.1-asr-flash-message`，显式开启 `intermediate_result_enabled`。中英混说并行辅助：`stt-rt-v6`。中文专家最重要的待对照替代：豆包 SeedASR 2.0 优化双向流式。**

这是一组可以立即进行 BYOK 接入与质量验证的架构基线，不能描述为“已证实 Qwen 在所有真实中文输入上最准确”。没有找到足够可靠的当前版本、相同音频、相同延迟预算、严格中文 CER / 混合 MER 的独立三方比较，能够完成这种绝对排名。

选择 Qwen Message 的理由是：官方提供适合听写的专门模型、真正双向输入、可开启的讲话中候选、句级修订与结束标识、真实词级时间、上下文和术语能力、北京与新加坡服务。这些能力可与独立英文专家共同工作，而不是先把整句判成中文后只送一个模型。该理由属于产品/工程适配判断；准确率领先仍须用 Saytile 已保存的真实输入音频检验。

Soniox v6 有 token 时间、语言标识和持续 final / non-final 协议，适合充当中英混说证据来源。它不再具有单一主模型地位，协议容易接入也不构成质量获胜证据。官方模型页标明 v6 于 2026-11-03 发布；旧 v5 的独立成绩不能自动归给 v6。

豆包 SeedASR 2.0 的优化双向流式方案能在讲话中输出并在句末用非流式处理再检查，直接符合本轮“实时与稳定输入也要提高准确率”的目标。其当选空间必须保留。当前工程实现先交付 Qwen + Soniox；没有把未实现的豆包适配器标成可用。

## 证据分层

| 证据 | 能支持什么 | 不能支持什么 |
|---|---|---|
| PR #4 已有 Apple / 本地 Qwen 实验、原始音频与测试记录 | 原设备上旧配置的表现、故障/派发契约、可复用的针对性样本 | 当前云 Qwen 3.1、SeedASR 2.0 或 Soniox v6 的质量排名 |
| PR #4 `public-evidence-snapshot`：Pipecat，固定 commit `94f567299a21f8d617039bc69f137a131f5dedd5` | 1000 条样本上的旧 `stt-rt-v5` 可用性、其指定语料/指标下的结果 | 当前 v6 质量；普通话真实听写；中英术语切换；第一批 partial 质量；严格 CER |
| 同一快照：Verli 2026-07-19 的 FLEURS 每语言 200 条 | 一家独立商业转写产品对若干服务的读句对照 | 最新精确模型版本、直播稳定前缀准确率、自发口语或中英混说优劣 |
| 阿里 / 火山 / Soniox 最新正式 API 与模型说明 | 型号、地域、协议、可请求参数、供应商声明的能力 | 独立识别率保证、统计显著的跨供应商排名 |
| 本轮协议 fixture tests | 我们对增量结果、UTF-16、真实时间、错误与最终状态的解析契约 | 网络端到端成功、实际延迟或真实识别质量 |

Pipecat 快照的 semantic WER 与 LLM 语义容错不能替代严格字词错误率；它的最后返回时间也不是首字出现时间。旧型号、不同语料、不同错误归一化都必须保持原标签。已有 Apple / Qwen 结果继续保留，无需为本次修订重跑。

原来源：

- https://github.com/pipecat-ai/stt-benchmark
- https://verli.app/blog/per-language-speech-to-text-accuracy
- 旧研究位置：[VENDORS.md](VENDORS.md)、[DECISION.md](DECISION.md)、[IMPLEMENTATION.md](IMPLEMENTATION.md)、[README.md](README.md) 及 [public-evidence-snapshot.json](results/public-evidence-snapshot.json)。

## Qwen 3.1：正式协议与已落实范围

### 型号与形态

- `qwen-audio-3.1-asr-flash-message`：听写/消息场景；中间结果需要显式打开。
- `qwen-audio-3.1-asr-flash-streaming`：连续实时场景，具有独立参数文档。
- `qwen-audio-3.1-asr-flash-filetrans`：文件处理。文件结果不能当实时结果。

本次 `QwenMessageProvider` **只接受 Message 这个明确型号**，不会假设旧 Qwen realtime、当前 streaming 和文件协议可以无条件交换。增加型号需要对应的协议验证。

官方总览与接入：

- https://help.aliyun.com/en/model-studio/asr-model
- https://help.aliyun.com/en/model-studio/qwen-asr-message-model-access
- https://help.aliyun.com/en/model-studio/qwen-audio-3-1-asr-flash-streaming

### 连接、音频与生命周期

| 项目 | 当前协议 / 实现 |
|---|---|
| 北京 | `wss://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference` |
| 新加坡 | `wss://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference` |
| 鉴权 | `Authorization: Bearer <API Key>`；Key、Workspace 与地域一致 |
| 音频 | 二进制 PCM，16 kHz、单声道、16-bit signed little-endian；不重复包装 WAV |
| 开始 | `header.action=run-task`，同一个 `task_id`，`streaming=duplex`；payload 是 audio/asr/recognition |
| 接收就绪 | 收到 `task-started` 后再发音频 |
| 结束 | 单一 writer 在全部音频之后发送 `finish-task`，继续读到 `task-finished` |

连接文档：

- https://help.aliyun.com/en/model-studio/qwen-audio-asr-streaming-websocket-api
- https://help.aliyun.com/en/model-studio/qwen-asr-message-websocket-api

### 候选、时间与上下文

Message `result-generated` 包含按 `sentence_id` 识别的句子；`sentence_end` 表示供应商句末结果。`stash` 可附下一句的临时内容，heartbeat 不构成转写。`begin_time/end_time`、stash `current_time` 与 words 的时间均按毫秒解释。没有凭字符数推导任何词级对齐，也没有填造语言标签或置信度。累计候选的 `audioStartSeconds` 固定为同一条录音的零点，片头静音之后的真实语音起点保留在 word/segment tokens 中；不能把首个语音时间误当成整个累计候选的窗口起点。

实现优先保留官方 `sentence.words` 中实际返回的 `begin_time/end_time/text/punctuation`，把原句中的空格附着到相邻词而不改动真实词时间，保证 tokens 拼接与原句 UTF-16 一致。词文本不匹配、遗漏原句内容、词时间无效或超出句时间时，退回原句及其真实 segment 时间。不能因为 words 漏了“不”或把“15”写成“50”，就同步改坏 sentence.text。全部有效词对齐时标为 `word`；存在句级降级时保留其他句子的真实词边界并保守标为 `segment`。如果临时句缺少任何真实结束时间，保留可见文本但降为无对齐的 `utterance` 证据。`task-finished` 时仍有非空未 final 句子会报 incomplete，不能伪造完整定稿。

请求打开 `intermediate_result_enabled`，关闭 `disfluency_removal_enabled`，开启 `keep_dialect` 以减少把原话改写成标准表达的意图。中英提示同时提供，不按整句主语言硬路由。

官方还提供 `input.context` 对话上下文、`vocabulary_id` 及内联术语权重；它们是识别偏置，不能成为新增词语的证据。本次共享配置只有 context 字段，故实现其文字上下文，不假装已经有术语管理 UI。Message 的单轮上下文按官方 400 字限制校验，超限明确报错，不暗中截断用户术语。

- https://help.aliyun.com/en/model-studio/qwen-asr-message-client-events
- https://help.aliyun.com/en/model-studio/qwen-asr-message-server-events
- QwenCloud 正式总览亦列出 Message 及词时间能力：https://docs.qwencloud.com/developer-guides/speech/asr-realtime
- 连续 streaming 的独立协议：https://help.aliyun.com/en/model-studio/qwen-audio-asr-streaming-client-events
- https://help.aliyun.com/en/model-studio/qwen-audio-asr-streaming-server-events

## Soniox v6：正式协议与已落实范围

- 型号 `stt-rt-v6` 与 `stt-async-v6` 的形态分开；本适配器只接受 `stt-rt-` 系列。
- 全球 WS：`wss://stt-rt.soniox.com/transcribe-websocket`。
- 连接采用 Bearer header；JSON `api_key` 已弃用，不放入可记录的请求正文。
- 原始 PCM 配置是 `audio_format=pcm_s16le`、`sample_rate=16000`、`num_channels=1`。
- 同时提示 `zh/en`，`language_hints_strict=false`；启用 token 语言标识与 endpoint detection，没有打开翻译。
- Soniox 没有文档规定的 `task-started`；开始配置成功写入后顺序发送音频。EOS 必须是**空文本帧**，空二进制帧不结束流。
- 文本按新 final token 追加、non-final 尾部整段替换。`<end>`/`<fin>` 是控制标记；不显示给用户。
- token 的原始 confidence 保存为 raw evidence，不校准就不能与其他模型比较。真实时间缺失时不假造对齐。累计候选 `audioStartSeconds=0`，真实 token 起点保持原值，使 Qwen、Soniox 与其他专家共享同一录音窗口。
- 同步读取 `finished`，错误按稳定类型归类，不记录供应商完整错误正文。`client_reference_id` 用于关联调用。

来源：

- https://docs.soniox.com/stt/models
- https://docs.soniox.com/api-reference/stt/websocket-api
- https://docs.soniox.com/stt/rt/real-time-transcription
- https://docs.soniox.com/authentication/websocket-authentication
- https://docs.soniox.com/stt/rt/endpoint-detection

## 豆包 SeedASR 2.0：必须保留的中文专家候选

官方提供优化双向：`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`；单向输入/句末输出：`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream`。新资源 ID 为 `volc.seedasr.sauc.duration` / `volc.seedasr.sauc.concurrent`，须与旧 `volc.bigasr.*` 分开。

当前接入说明使用 `X-Api-Key`、资源 ID 与 request ID；PCM 建议 16 kHz、16-bit、mono。语言、标点、ITN、口语删除等参数不是与其他厂商相同的通用 JSON。尤其 `enable_ddc` 类口语删除选项需要保守关闭并用反例验证，不能默认“更顺畅”等于更忠实。

RTC 集成文档明确区分流式模式和优化双向模式：优化模式在实时结果后增加句末非流式处理，相关开关为 `request.enable_nonstream=true`。文档指出 SeedASR 2.0 支持指定的单向/优化双向模式；不能直接拿旧 1.0 的配置号认作 2.0。

这些是可用能力与供应商技术路线的事实，不是独立证明 SeedASR 胜过当前 Qwen 的识别成绩。账户开通、地区连通和实际权限仍需用用户授权的 BYOK 核验。

- https://docs.volcengine.com/docs/doubao-voice/bidirectional-streaming-automatic-speech-recognition-websocket?lang=en
- https://docs.volcengine.com/docs/doubao-voice/unidirectional-streaming-automatic-speech-recognition-websocket?lang=en
- https://docs.volcengine.com/docs/real-time-communication/quick-integrate-custom-agent-via-gateway?lang=en

## 工程交付与明确边界

初始适配器提交 `6ad2dba`；本研究文件与累计窗口起点修复作为后续独立提交保存：

- `Sources/SaytileKit/QwenMessageProvider.swift`
- `Sources/SaytileKit/SonioxStreamingProvider.swift`
- `tests/SaytileKitTests/ChineseProviderProtocolTests.swift`

二者遵守 `StreamingASRProvider.run(audio:configuration:credential:emit:)`，使用 macOS Foundation `URLSessionWebSocketTask`，不额外依赖语言绑定 SDK。厂商 JSON 分别解析；只共享超时/串行写入/取消等传输机制。

连接或一次写入的等待上限为 20 秒；EOS 之后最多等待 45 秒完成 drain。它们是故障检测预算，**不是最高质量模式的稳定文本等待策略**。长语音不会按固定语句秒数强行提交；供应商 final 也不直接触发外部派发。取消会关闭 socket 以解除挂起读取；任何错误均交回统一协调器，原音保存不归 provider 控制。

13 个协议 fixture 覆盖：Qwen 地域和就绪契约、明确 partial 开关、同句更新、UTF-16 emoji、下一句 stash、heartbeat、缺时间降级、错误代次、不完整 final、Soniox 增量规则与语言、控制标记、header auth、非翻译、错误脱敏，两个供应商在片头静音情况下的累计窗口与真实语音起点，以及 Qwen 真实词边界/标点空格保留、错词和无效时间的句级降级。这些 fixture 不产生服务费用。

本容器没有 Swift 编译器；编译和 fixture 运行交给 root 的 Mac 验证，不把静态检查称为“测试通过”。下一项准确率证据应是用户授权的少量真实音频：否定词、金额/单位、重复表达、中文带 SwiftUI/SQLite/ChatGPT、低 SNR 与自然切换，并分别记录首字、中间修订、可派发稳定结果和完整复核四个阶段。未经这一步，不发布“最高准确率已经验证”的表述。
