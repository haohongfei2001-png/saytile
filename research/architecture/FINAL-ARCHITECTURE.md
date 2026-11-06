# Saytile：双平等专家 + 唯一 GPT 核心

更新：2026-11-07。本文件是用户最新决定，取代旧单主模型、自适应语言切分、多 AI 仲裁链与多稿件 UI。以下是验收契约，不是对所有功能均已实现的声明；实际状态见 PROJECT-STATUS.md 与后续独立工程 PR。

## 产品与数据通路

```text
持续采集 -> 独立 PCMJournal / durable watermark -> 有界独立音频通道
                                                   |-- 中文专家：完整音频 --|
                                                   |-- 英文专家：完整音频 --|-> Candidate Store
                                                   |-- 可选第三 ASR -------|
离线/可选本地 Apple SpeechAnalyzer -------------------------------> 同一 Candidate Store
Candidate Store -> SingleTranscriptEngine <-> 唯一 GPT-6 Astra 文本会话
                -> 一份可修正文字 -> 本地输入板 / 个人语音档案
                -> 独立目标绑定、UTF-16 所有权账本 -> 外部草稿的追加/安全局部修正
```

中文/英文只是主要质量职责，不是单语言解码限制。两路自始至终接收相同音频，不预切语言、不按句路由、不预设主模型。任一路慢或失败不得阻塞录音落盘。第三路仅在同音频实测有准确率净收益后启用。原音与文字独立存在，删除原音不删除用户文字。

## 唯一文字流

用户只看一份持续出现、自然修正的文字；无多模型结果、版本选择、Raw/Formatted、润色模式或模型调度 UI。内部保留来源与修订证据，不改变这一体验。忠实转写保留口语、否定、数字、单位及有意重复；不是 Wispr 式自动清理 false starts。允许转写所需标点，禁止改写、扩写、总结、翻译。用户编辑优先，后台不得覆盖。

## GPT 能力与时序

官方 GPT-6 Astra 模型页明确 Audio not supported；`gpt-6-astra` 经 Responses 做文本证据融合，不能宣称听过原音。独立 OpenAI 音频型号不等于 GPT-6。A-F 中 F 为 NOT_AVAILABLE，不假执行。

持续参与不是每 token 请求。候选事件合并窗口以 280ms 为工程起点；它不等于 GPT 延迟，也不是正确性超时。每录音/识别代次仅一条 GPT 会话、一个在途评审；新证据合并，旧响应仅在来源片段逐字不变且时间证据仍有效时可重基，否则拒绝并处理最新快照。两 ASR EOS 后，即使一致也执行最终 GPT 复核；失败不伪装完成或反复无限重试。

WebSocket Responses 支持 `response.create`、`stream_id` 和 `previous_response_id`：前者 lane 是 FIFO，不表示上下文；后者表示 lineage。`store=false` 依赖连接内缓存。断线、60 分钟连接上限或 `previous_response_not_found` 后清掉旧 response ID，以有界完整权威快照恢复。候选变更用增量及当前身份清单表达；过期候选从引用集合中移除。只接收完整、通过 schema/来源校验的选择，不能将未完成 JSON 作为用户文字。HTTP SSE 可作为同一 GPT 的受控替代，不构成第二仲裁层。

GPT 只能选择真实候选及 UTF-16 span。未听音时不能增加候选中不存在的词。没有真实词时间不能伪造词级拼接；模型置信度不能跨供应商当概率比较。无法消歧保留可信现文与不确定状态，不凭常识猜测。

## 外部草稿可以修正，但必须有所有权

不再把“曾派发”一概等同永久不可修改。只允许修改 Saytile 能严格证明仍拥有的精确文本范围：同一绑定、应用/窗口/控件/页面、预期原文相同、范围/字素边界有效、用户未编辑该范围。采用局部替换，禁止整框重写。位置、焦点、原文或能力不可信则修正留待处理；不得追加重复全文。保留至多一次自动尝试、崩溃不自动重放、不发送、不回车。未知投递不能假定已成功。

## 离线、原音与授权

Apple 结果进入统一候选与发布入口，不再单独直接写正式稿。断网后录音照常，本地资源/语言可用时转写，不可用则明确排队；恢复必须重新检查授权、代次与已派发范围。原音区间读从 journal/chunks 的真实 sample range 与持久化水位取得，跨块读取且有单请求内存上限；不依赖 12MB 生命周期缓存。每项服务独立 Keychain/音频或文本授权；撤销立即取消会话及上下文，不能上传旧音频到新配置。

## 官方来源（2026-11-07 查阅；能力披露，不是本产品实测）

- https://developers.openai.com/api/docs/models/gpt-6-astra
- https://developers.openai.com/api/docs/guides/websocket-mode
- https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform
- https://help.aliyun.com/zh/model-studio/qwen-asr-message-websocket-api
- https://www.assemblyai.com/blog/universal-3-6-pro-realtime
- https://docs.soniox.com/stt/models

ChatGPT 与 API 分开计费；符合条件的订阅可能有需关联 API 组织的促销额度，不能笼统说所有 Pro 都无 API 额度。订阅本身不代替 API Key、服务权限、处理授权或实际余额核对。
