# ASR 最终方案：供应商与证据附录

核验日期：**2026-11-06**。本文支持 `DECISION.md` 与 `IMPLEMENTATION.md`，记录选型边界、当前接口事实和公开证据；不继续建设公共 benchmark，不新增云端调用。

## 1. 固定方案与候选边界

| 角色 | 引擎 | 本轮决策 |
|---|---|---|
| 唯一默认云端实时引擎 | **Soniox `stt-rt-v6`** | 中文、英文、中英混说走同一个实时会话；不按语言切换供应商，不默认二次 ASR。 |
| 离线与云端故障备用 | **Apple SpeechAnalyzer / SpeechTranscriber** | 保留本地可用性；结果按实际引擎标记，不冒充云端结果。 |
| 唯一地区替代候选 | **Qwen `qwen-audio-3.1-asr-flash-message`** | 仅当实际大陆网络条件无法支撑 Soniox 时再考虑替换云端供应商；本轮不并行接入，不自动双跑。 |
| 未来手动重转写候选 | **ElevenLabs `scribe_v2`** | 尚未选型；仅保留未来用户主动重转写的可能性，不进入默认流水线。 |

这是综合公开质量证据、实时协议、混说能力和工程复杂度作出的**技术选择**，不宣称 Soniox 在所有中文或英文榜单第一。Soniox `stt-async-v6` 虽然存在，但不因此增加第二遍默认识别。原音独立保存、文字版本、稳定 UTF-16 增量派发、防重复和目标保护均继续保留。

## 2. Soniox：必须遵守的当前协议

- **模型版本：** `stt-rt-v6` 于 **2026-11-03** 发布；Pipecat 已公开的相关实测行是 **`stt-rt-v5`**。旧版第三方结果支持产品系列的选择，不能改写为 v6 已获同样成绩。[官方模型目录](https://docs.soniox.com/stt/models)
- **端点与鉴权：** `wss://stt-rt.soniox.com/transcribe-websocket`。在 WebSocket **Upgrade 请求头**发送 `Authorization: Bearer <key>`；新实现不把 `api_key` 放进首个 JSON 配置。连接打开后仍需处理服务端鉴权错误帧，不能将握手成功当作鉴权完成。[鉴权文档](https://docs.soniox.com/authentication/websocket-authentication)
- **音频与语言：** 首个文本消息配置 `model: "stt-rt-v6"`、`language_hints: ["zh", "en"]`。音频使用二进制帧；原始 PCM 必须声明真实格式、`sample_rate` 和 `num_channels`，与 Saytile 保存的音频时钟对应。语言提示不是先做中文/英文分流的理由。[WebSocket API](https://docs.soniox.com/api-reference/stt/websocket-api)
- **稳定派发：** `is_final: true` 的 token 才进入稳定前缀；未 final 的尾部只更新预览。供应商 final 不代替 Saytile 的录音代次、源音频范围、UTF-16 游标及目标绑定校验。[WebSocket API：Response](https://docs.soniox.com/api-reference/stt/websocket-api#response)
- **结束协议：必须发送空文本帧 `""`**，Swift 对应 `.string("")`。空二进制帧只是空音频块，**不会结束流**。发送后继续读取最终响应与 `finished`，不要立即取消连接。[WebSocket API：Ending the stream](https://docs.soniox.com/api-reference/stt/websocket-api#ending-the-stream)
- **密钥：** 个人自带 key 由 Keychain 保存；发行版不内置共享长期密钥。面向用户的托管服务使用短期凭据或受控后端。当前官方鉴权文档支持临时 key；不需要为本次技术裁决开通账户或收费服务。[鉴权文档](https://docs.soniox.com/authentication/websocket-authentication)

现有 Pipecat 流式集成及其公开可运行评测说明 Soniox 已有第三方框架接入路径；这不等同于 Saytile 的 Swift 集成已验收。正式实现采用原生 `URLSessionWebSocketTask` 时，按上述**当前**协议实现，不机械复制旧 SDK 示例。

## 3. 其他供应商：保留准确名称，不扩展实现范围

| 供应商 | 本次核验的官方模型 / 接口 | 对本方案的意义 |
|---|---|---|
| Qwen | `qwen-audio-3.1-asr-flash-message`（语音输入、句末修订）；`…-streaming`（连续识别）；`…-filetrans`（文件）。[模型总览](https://help.aliyun.cn/zh/model-studio/asr-model) · [Message API](https://help.aliyun.com/en/model-studio/qwen-asr-message-websocket-api) | Message 的内部修订可能省去自建双引擎，但可修订中间稿不能直接当不可变前缀。仅保留大陆网络条件不满足时的替代候选；已有聊天权限不代表 ASR 权限。 |
| ElevenLabs | 文件 `scribe_v2`，实时 `scribe_v2_realtime`；`xi-api-key` 鉴权。实时 `partial_transcript` 可变，`committed_transcript` 才稳定。[文件 API](https://elevenlabs.io/docs/api-reference/speech-to-text/convert) · [实时 API](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime) | 只保留 `scribe_v2` 为未来手动重转写候选；不开启默认二次识别，也不把 `transcript_edit` 改写当原始 ASR。 |
| OpenAI | `gpt-live-transcribe` 用于实时，`gpt-transcribe` 用于文件/提交音频段；Bearer API key。文件 `POST /v1/audio/transcriptions`。[转写指南](https://developers.openai.com/api/docs/guides/speech-to-text) · [实时指南](https://developers.openai.com/api/docs/guides/realtime-transcription) | 本轮不接入。ChatGPT Pro 不等于 API 权限。文件 SSE 不等于麦克风实时首字。 |
| 豆包 | 流式 2.0 `doubao-seed-asr-2.0`，资源 `volc.seedasr.sauc.duration`；文件 2.0 资源 `volc.seedasr.auc`。新控制台 `X-Api-Key`，旧控制台 App ID + Access Token。[官方方案](https://console.volcengine.com/ark/region%3Acn-beijing/docs/agent-plan-personal-voice-model) · [文件 API](https://docs.volcengine.com/docs/doubao-voice/large-model-recording-file-recognition-standard-version-api?lang=en) | 本轮不接入。模型名称、计费资源 ID 与鉴权字段不能混用；方舟聊天权限不能替代语音产品权限。 |

## 4. 来源、证据级别与可推出的结论

所有 URL 的核验日期均为 2026-11-06；动态榜单后续可能更新。以下数字记录本次核验快照，不能把不同版本页面的数值拼成一次实验。

| 级别 | 来源 | 本次采用的证据与限制 |
|---|---|---|
| **独立第三方、可运行评测** | [Pipecat STT benchmark](https://github.com/pipecat-ai/stt-benchmark)；[TTFS 定义](https://github.com/pipecat-ai/stt-benchmark/blob/main/docs/measuring-ttfs.md) | 1,000 个 smart-turn 样本；Soniox **v5** 的 pooled semantic WER 为 **1.09%**，TTFS 中位数 **260 ms**、P95 **305 ms**。semantic WER 经 LLM 语义评分并忽略部分填充/复述及格式差异，不能当逐字 WER，更不能当中文 CER。**TTFS 是停声至最终转写到达，不是首字延迟。** 它不证明 v6 或普通话混说的相同成绩。 |
| **第三方商业应用公开测量** | [Verli 分语言比较，2026-07-19](https://verli.app/blog/per-language-speech-to-text-accuracy) | 每语言 200 条 FLEURS 朗读样本。报告中的中文 CER：Scribe **4.17%**、gpt-4o-transcribe **4.46%**、Soniox **4.71%**；须连同成功覆盖率解释，不能只按错误率排序。版本早于当前选型，且未包括 Qwen 与自然中英混说。支持“Soniox 中文可竞争”，不支持“中文冠军”。 |
| **厂商官方技术文档** | 本文第 2、3 节的 Soniox、Qwen、ElevenLabs、OpenAI、豆包文档 | 支持模型 ID、端点、鉴权、音频格式、事件语义和公开功能。多语言/混说功能声明不等于独立实测准确率。 |
| **厂商营销或转述** | [Soniox benchmarks 页面](https://soniox.com/benchmarks) | 即便引用 Pipecat，仍优先使用 Pipecat 原始仓库及指标定义；不把厂商页面算成新增独立证据。 |
| **本项目本地记录** | `results/direct/`；恢复的 `../asr-2026-11-06/results/` | Apple、本地 Qwen3-ASR-1.7B、Whisper 的有限结果只说明对应本地运行。不能当作 Soniox、Qwen-Audio 3.1 云端或 OpenAI 现行服务的成绩。 |
| **工程推断与选型** | `DECISION.md`、`IMPLEMENTATION.md` | 单引擎能减少额外网络、第二遍费用与修订冲突；结合公开质量和协议证据选择 Soniox。保留备用并不等于并行运行。属于明确技术裁决，不伪装成已完成的五家云端实测。 |

**中英混说证据边界：** [Perle ASR benchmark](https://perle.ai/benchmark/asr/) 与 [ServiceNow code-switching 研究](https://huggingface.co/blog/ServiceNow-AI/code-switching) 的所列混说证据未覆盖普通话，不能用来证明 Mandarin–English 成绩。单语言中文与英文榜也不能合成为未经测量的中英混说准确率。这个缺口应作为对外准确率表述的边界，不能演变为继续扩大研究或推迟本轮选型的理由。
