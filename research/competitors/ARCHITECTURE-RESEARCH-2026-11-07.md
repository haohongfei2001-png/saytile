# 全球语音输入竞品架构研究

研究日期：2026-11-07。范围：公开官方文档、开发者文档、产品帮助中心及公开代码。**竞品内部服务拓扑、模型训练数据、真实端侧/云端分配未公开的部分一律标为未知**。产品宣传的准确率和延迟不是独立测量结果。

## 1. 执行摘要

头部产品并不存在一个共同的“多模型并行 ASR”范式。公开材料更支持以下分化：

- Aqua Voice：以自研 Avalon ASR 为核心，突出面向人机交互/编程词汇的模型训练；Deep Context 是可选、按一次 dictation 触发的屏幕词汇提取，不是持续录屏。
- Wispr Flow：云端语音转写加上下文和后处理体验，提供 Smart Formatting、Backtrack、上下文感知；官方披露其本地采集并发送应用/文本/屏幕等上下文的范围，隐私开关和字段排除非常值得研究。
- Superwhisper：把 ASR 与可选 LLM 后处理分成两个可组合阶段；用户可在本地模型、托管云模型和自带 API key 之间选择，模式定义何时用哪种模型及输出方式。
- Willow：产品层提供 Frontier Pro/Mini、个人词典、自动学习、风格适应和 Mac/iOS Offline Mode；但模型内部结构、端云调度和离线模型细节没有充分公开，不能推定。
- VoiceInk：模型目录与 Mode 分离，允许本地/云/自定义模型、独立 enhancement prompt、上下文和输出方式，是可组合性和可控性的直接参照。
- Typeless：隐私说明明确写出音频与有限上下文实时发送云端、返回后即丢弃；云端识别、端侧历史文本和可选云同步的边界透明。内部 ASR 模型和多模型策略未知。
- Apple SpeechAnalyzer：提供真正值得 Saytile 直接复用的系统级本地流式能力；volatile/final 结果、音频时间范围、模型资产管理、异步序列和资源限制均有公开 API。

**核心学习：竞争力不来自把更多模型同时打开，而来自一个可靠的表达生命周期：持续捕获、低延迟预览、证据增强、可撤销的文本整理、上下文适配、用户可控输入，以及原音/历史恢复。**

## 2. 证据矩阵

| 产品 | 采集/触发 | ASR 架构（已披露） | 上下文/个性化 | 后处理 | 离线/恢复 | 证据等级与未知 |
|---|---|---|---|---|---|---|
| Aqua Voice | 桌面 push-to-talk / 即时与 Realtime 模式；不是官方承诺的常开采集 | 自研 Avalon；API 提供批量转写；Realtime Mode 产品可用，但完整内部流式拓扑未披露 | Deep Context 开启后在 dictation 开始时截取一次屏幕，抽取可能说出的名字/代码；与长期 Dictionary 分开 | 产品定位为直接转写，具体内部 LLM cleanup 细节未知 | 屏幕图像称处理后不保留；整体离线能力未充分披露 | 官方产品页/模型说明；Avalon 训练数据细节未知 |
| Wispr Flow | 用户触发录音，自动转写输入；本地采集上下文 | 官方文档描述云端请求与本地音频保存/重试；具体 ASR 模型及是否多模型未知 | app、文本框光标前后、选中文本、屏幕文字/截图、代码变量/文件名、部分会话上下文；密码和部分敏感字段排除 | Smart Formatting、Auto Cleanup、Backtrack；保留原始 dictation 并可 Undo AI edit | 音频本地短期保存，失败可 Retry；音频保留期限有产品政策 | 官方帮助中心；内部模型编排未知 |
| Superwhisper | 录音快捷键/Mode；偏录制后交付的可配置工作流 | 本地 Whisper/Parakeet/S1 等，或云模型；ASR 与 LLM 两阶段 | Mode 可绑定 app/website/trigger，提供 selected text、clipboard、screen text | 独立 Super Mode / LLM，可选择是否执行；本地/云均可 | 本地模型可完全离线；云处理与 BYOK 的数据流有隐私说明 | 官方模型目录、隐私政策；厂商 benchmark 非独立测评 |
| Willow | 按住热键或 hands-free 模式；结果粘贴当前光标 | Frontier Pro/Mini 品牌模型；Offline Mode 在 Mac/iOS；模型细节未知 | 个人词典、Auto-learning Dictionary、写作风格记忆、应用语境 | Smart formatting、Scribe 与风格适配 | Mac/iOS Offline Mode；历史和失败重试可用 | 官方网站/帮助中心；Frontier 内部模型和云端编排未知 |
| VoiceInk | 快捷键/录音；Mode 选择触发器 | 本地 Parakeet、Nemotron、Whisper、Cohere、Apple Speech；云 provider 和自定义 OpenAI-compatible endpoint | Mode 可选 selected text、clipboard、screen text；app/site/shortcut/voice trigger | 独立 AI Enhancement provider/model/prompt；可关闭；输出 Paste/Respond/Custom Command | 本地模型离线；云模型取决于网络；导入文件不使用实时上下文/派发 | 官方文档和配置界面；每个第三方模型质量仍需单独验证 |
| Typeless | 用户触发跨应用语音输入 | 官方说明云端 transcription；具体模型和多模型策略未知 | 有限 app 信息和相关文本上下文随音频发送 | context-aware formatting / cleanup；内部步骤未披露 | 官方称音频和上下文返回后即丢弃；历史文本本地，云同步可选 | 官方隐私政策/数据控制；服务端拓扑未知 |
| Apple SpeechAnalyzer | 应用控制采集，支持实时音频序列/文件 | SpeechAnalyzer + SpeechTranscriber；系统本地模型资产 | 不提供通用屏幕上下文；可由 app 自己管理 AnalysisContext | 由应用决定后处理 | 模型资产由系统管理；本地处理，语言与设备支持需运行时检查 | Apple Developer 文档/WWDC25；具体模型权重不公开 |

## 3. 产品级机制拆解

### Aqua Voice：领域识别 + 临时上下文

官方 Avalon 介绍称其针对 human-computer interaction，尤其是软件、命令、产品和技术术语，并给出 OpenASR 的厂商 benchmark。该数据可以支持“专门训练领域表达值得做”，不能证明它在 Saytile 的中英混说上胜过所有模型。

Deep Context 的机制披露较具体：用户开启后，dictation 开始时拍一张屏幕截图，抽取名称/术语/代码；不持续录屏，不保留截图，提取出的词汇与该次 dictation 关联；完成时间若晚于转写，不阻塞文本插入。长期 Dictionary 与本次屏幕临时词汇并行。这是非常适合 Saytile 的“上下文增益但不延迟核心路径”设计。

Saytile V1 不复制自动截图；先做明确授权的 app identity、用户主动选中文本和手工术语提示。可选屏幕上下文放在 V2+ 的独立开关与隐私评审中。

来源：
- https://aquavoice.com/blog/introducing-avalon
- https://aquavoice.com/guide/how-to-use-avalon
- https://aquavoice.com/deep-context
- https://aquavoice.com/docs/api

### Wispr Flow：表达修正和上下文适配

官方 Backtrack 说明系统使用整段 dictation 判断“actually / scratch that”等自我修正，删除 false starts/fillers；同时强调普通语义里的 actually 不应被误删。Smart Formatting 处理标点、大小写、列表和段落，不等于纠正 ASR 错词。桌面端可 Undo AI edit 回到原始转写，Retry transcript 则重新识别；失败录音通常可从本地历史恢复。

Context Awareness 文档列出 app、光标前后文本、选区、屏幕文字、代码文件名/变量、部分对话历史等上下文。文档也披露字段排除、金融 app 排除和 Privacy Mode。其价值不只是“多给模型一点 prompt”，而是建立了可解释的上下文收集与敏感字段边界。

Saytile 应将 raw transcript、formatted transcript、user-edited transcript 分开保存；格式化不得冒充声学纠错；必须一键还原原文。Backtrack 先只作用于尚未派发的当前表达，禁止回改已输入外部应用的内容。

来源：
- https://docs.wisprflow.ai/articles/5373093536-How-do-I-use-Smart-Formatting-%26-Backtrack
- https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness
- https://docs.wisprflow.ai/articles/4048537120-what-to-expect-from-flow-accuracy-and-known-limitations

### Superwhisper：ASR 与文本转换分离

Superwhisper 官方模型说明明确将流程拆成两阶段：语音识别模型将音频变成文字；可选语言模型按 Super Mode 重写/格式化。两阶段可以混搭，例如本地 Parakeet + 云端 Claude，或本地识别后不做 LLM。隐私政策也区分本地模型、Superwhisper 托管云模型、第三方 provider 与 BYOK 直连。

这证明“识别文本”和“用户希望如何表达”是不同问题。Saytile 应保留 raw ASR transcript，格式化/写作增强作为独立、可关闭、可撤销的 transformation。V1 的默认直接输入不能暗中变成 LLM 改写。

来源：
- https://superwhisper.com/models
- https://superwhisper.com/privacy
- https://superwhisper.com/offline-transcription
- https://superwhisper.com/changelog

### Willow：低摩擦输入、个性化与离线承诺

官方帮助中心描述按住热键说话、松开后插入，以及 hands-free mode；官网与帮助中心宣称个人词典、自动词典学习、风格匹配和 Offline Mode。离线模式官方博客/产品资料指出 Mac 与 iOS 可用，Windows 仍依赖云端。具体 Frontier Pro/Mini 模型结构、在线与离线是否同源、自动学习的训练/存储算法没有公开技术证明。

值得学习的是“用户无需选择模型即可得到符合语境的成稿”和可学习的术语体验。不能照搬“自动学习”而不要求用户确认纠错证据；Saytile V1 可先保存用户明确修正事件，V3 再形成个人词典。

来源：
- https://willowvoice.com/
- https://help.willowvoice.com/en/articles/10876920-dictating-with-willow-voice
- https://help.willowvoice.com/en/articles/12279120-dictation-quality-or-transcription-failure-problem
- https://willowvoice.com/blog/understanding-ai-voice-dictation

### VoiceInk：模型目录与工作模式正交

VoiceInk 文档将 AI Models Catalog（有哪些 ASR/LLM provider 可用）与 Mode（在什么场景选择哪个 ASR、语言、增强提示词、上下文和输出方式）分开。支持本地模型、云 provider、OpenAI-compatible 自定义端点；但自定义转写接口可能仅支持 batch 而无实时 partial。其 Mode 可按 app/site/shortcut 触发，使用选区/剪贴板/屏幕文本，输出 Paste、Respond 或 Custom Command。

Saytile 可借鉴配置与运行策略分离，但 V1 不需要复杂的任意工作流市场。把“模型目录/凭据”与“质量策略/场景规则”分离，避免每个模型配置同时承担产品行为。

来源：
- https://tryvoiceink.com/docs/ai-models
- https://tryvoiceink.com/docs/modes
- https://tryvoiceink.com/docs/custom-models
- https://tryvoiceink.com/docs/mode-settings

### Typeless：云端高质量与数据最小化说明

Typeless 的公开隐私文件称音频和有限上下文在云端实时处理并在结果返回后丢弃；历史文字默认留设备，可选云同步。其“高质量依赖云端”的产品判断与 Saytile 目标并不冲突，关键在于云端处理和长期存储是两回事。内部 ASR、LLM、模型并行与延迟机制未知。

来源：
- https://www.typeless.com/privacy
- https://www.typeless.com/data-controls

## 4. Apple SpeechAnalyzer：可直接采用的工程范式

Apple WWDC25 展示了 SpeechAnalyzer/SpeechTranscriber 的流式架构：
- Analyzer 管理模块与异步输入/结果序列。
- SpeechTranscriber 可提供 volatile 与 finalized 结果；volatile 是快速但可能变化的预览。
- AttributedString 可附 audioTimeRange，支持把文本范围映射回原音时间。
- 输入缓冲先转换为 bestAvailableAudioFormat，再进入 Analyzer。
- App 可同时把音频写入磁盘；ASR 与原音持久化可并行。
- 通过 finalize/finish 正确收尾；错误后创建新 Analyzer 恢复剩余输入。
- 系统管理模型资产；prepareToAnalyze 可预热，但资源受设备约束。
- ignoresResourceLimits 是危险的 beta 能力，不应作为生产默认。

重要的是，Apple 已经示范了“录音写盘 + 实时转写 + volatile/final 分层 + 时间戳”的完整基本模式。Saytile 不应自行重造这一层。

来源：
- https://developer.apple.com/videos/play/wwdc2025/277/
- https://developer.apple.com/documentation/speech/speechanalyzer
- https://developer.apple.com/documentation/speech/bringing-advanced-speech-to-text-capabilities-to-your-app

## 5. 模型与服务的技术启示

Soniox STT v6（2026-11-03 发布）公开支持 60+ 语言、token 级语言标签、句内切换和实时/异步接口；实时 token 有 is_final 状态。它是当前应当加入 Saytile 同输入基准的混说候选。v5 历史成绩不得套用到 v6。

Qwen3-ASR 公开发布 0.6B/1.7B 多语言模型和独立 ForcedAligner 0.6B；ASR 支持 52 种语言/方言，streaming 目前官方说明依赖 vLLM 后端；ForcedAligner 可给 11 种语言输出词/字时间戳。它是本地离线候选，但不等于在 M5 24GB 上可直接达到实时性能。需实际测模型加载、首 token、实时因子、内存、温度、续航和中英混说准确率。

来源：
- https://docs.soniox.com/stt/models
- https://docs.soniox.com/stt/concepts/context
- https://docs.soniox.com/stt/concepts/supported-languages
- https://github.com/QwenLM/Qwen3-ASR

## 6. Saytile 应吸收的竞品能力优先级

| 能力 | 来源 | Saytile 决策 |
|---|---|---|
| ASR 与文本转换分离、可撤销 | Superwhisper / Wispr | V1 必须 |
| Backtrack 语音自我修正 | Wispr | V1 限于未派发表达 |
| app/选区上下文 | Wispr / VoiceInk | V1 最小权限版 |
| 一次性临时屏幕词汇 | Aqua | V2 可选，V1 不自动截屏 |
| 个人词典和确认式学习 | Aqua / Willow | V1 记录纠错事件，V3 正式学习 |
| 本地/云模型可组合 | Superwhisper / VoiceInk | V1 采用适配器与策略分离 |
| 断网离线工作 | Superwhisper / Willow / Apple | V1 原音持续保存 + 本地可用 ASR |
| Mode 触发策略 | VoiceInk | V1 只做少量场景策略，不做任意工作流平台 |
| Undo 原文 | Wispr | V1 必须保留 raw transcript 和版本回滚 |

## 7. 明确未知与后续核实

- Aqua Avalon 的真实实时服务端拓扑、训练语料、模型规模、模型是否与批量 API 相同：未知。
- Wispr Flow 内部 ASR 供应商/自研模型、是否并行：未知。
- Superwhisper 自研 S1/Ultra 的权重与训练方案：未知。
- Willow Frontier Pro/Mini 的模型结构、端云路由和自动词典算法：未知。
- Typeless 的底层 ASR/LLM 与多模型策略：未知。
- 所有厂商宣传的“几倍准确率/200ms”缺乏与 Saytile 同条件、独立、公开可复现的证据。
