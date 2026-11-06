# Saytile V1 最终技术架构裁决

日期：2026-11-07。依据：当前 PR #4 工程、V1 产品设计、Apple/Soniox/Qwen 官方技术资料和竞品研究。

## 1. 最终结论

采用 **持久化优先、质量驱动的自适应混合架构**（Durable Capture + Adaptive Hybrid Recognition）。

不是纯云端、纯本地，也不是每段音频始终并行运行全部模型。

### 决策

1. Capture 与 PCMJournal 永远先于识别，并且完全独立。网络、ASR、LLM、目标应用都不能阻塞采集和落盘。
2. 默认云端高质量路径采用一条强多语言流式主路作为混说基线（优先将 Soniox STT v6 纳入真实 A/B；不能把官方 v6 新能力当作已经验证）。它提供逐 token 语言标签和 code-switch 支持，适合中英句内切换。
3. Qwen Message、AssemblyAI、Meta Muse 保留为可选专家/挑战者。按语言片段、领域、主路不确定性、错误类型和实测边际收益调度，不默认每次全部开启。
4. Apple SpeechAnalyzer 成为统一协调体系中的本地持续基线/离线 fallback，不再与云端互斥。其角色是可用性和离线连续性，不预设其中文准确率优于云端。
5. 对 M5 24GB，可单独评估 Qwen3-ASR 0.6B 作为可下载的本地增强/离线挑战模型；1.7B 和 ForcedAligner 不直接默认常驻。只有在实测实时因子、内存、热负载和准确率达到门槛后才启用。
6. 文本 LLM 仅在有意义的候选冲突、上下文纠错或表达格式化时触发。它不能创造声学证据，也不拥有写正式 transcript / dispatch ledger 的权限。
7. 原音复听使用真正的音频输入模型，优先只截取有争议的短片段并保留上下文边界；全段复听是 fallback，不应每条录音无条件执行。
8. ASR 与文本转换分离。Raw transcript 是不可被格式化覆盖的原始识别版本；formatted draft 可撤销；user-edited draft 最高优先级。
9. “稳定前缀”必须是可解释的 evidence state，不是模型 final 或定时器。未解决数字、否定、实体、单位和时间冲突时停止推进。
10. 直接输入仍遵守当前 UTF-16 范围账本：不自动发送、不回车、不重写全文、不重放不确定投递。

## 2. A-E 方案比较

| 方案 | 识别质量上限 | 离线 | 延迟/成本 | 复杂度/风险 | 裁决 |
|---|---|---|---|---|---|
| A 纯云多模型 | 高，但依赖网络和模型组合；冗余可能相关错误 | 无 | 多请求、高费用 | 网络成为生命线 | 不选 |
| B 纯本地多模型 | 设备允许范围内；强模型吞吐和热约束未知 | 强 | 无云费用但有设备成本 | 下载、内存、能耗、运行时复杂 | 不选作默认 |
| C 本地优先、云端补疑难 | 离线连续，但本地先验质量决定首显 | 强 | 本地持续占用，云请求少 | 本地弱结果可能污染用户感知 | 仅作离线策略 |
| D 本地+云始终并行 | 理论证据多，错误相关性仍存在 | 部分 | 长期耗电/费用/上传量最高 | 无法证明所有请求都带来增益 | 不选 |
| E 自适应混合 | 按任务选择最有价值的证据，质量/资源可调 | 强（本地能力范围内） | 可控 | 调度器和可观测性要求高 | **选择** |

## 3. 统一数据流

```text
Microphone / CoreAudio
        |
        v
CaptureWorker -----> AudioHealth / device monitor
        |
        +-----> PCMJournal (durable local audio; chunk + checksum + fsync policy)
        |                |
        |                +-----> Recovery Queue / Retry Scheduler
        |                |
        |                +-----> Playback / Export / Delete lifecycle
        |
        v
VAD + Segmenter (non-destructive; source sample clock)
        |
        +-----> Apple SpeechAnalyzer (local baseline / offline fallback)
        |
        +-----> Recognition Policy Engine <----- Network / thermal / power / language / context
                        |
                        +-----> Primary multilingual stream (Soniox v6 A/B baseline)
                        |
                        +-----> Optional specialist streams (Qwen / Assembly / Meta)
                        |
                        +-----> Targeted final ASR (async/file model when needed)
                                      |
                                      v
                          Candidate Store (immutable source evidence)
                                      |
                   +------------------+-------------------+
                   |                                      |
                   v                                      v
           Alignment / LID / Risk                  Context Engine
           (sample clock, real word times,         (app identity, user selection,
            token language, confidence local)      explicit terms; opt-in only)
                   |                                      |
                   +------------------+-------------------+
                                      |
                                      v
                            Evidence Fusion Coordinator
                           /                         \
                  Text arbiter (only conflict)     Audio review (only ambiguity)
                           \                         /
                                      |
                                      v
                           Transcript Version Store
                        raw / stable / formatted / user
                                      |
                         +------------+-------------+
                         |                          |
                         v                          v
                 Search / Playback             Direct Input
                                                (existing ledger)
```

## 4. 模块职责与协议

| 模块 | 输入 → 输出 | 持久化 | 约束 |
|---|---|---|---|
| CaptureWorker | CoreAudio buffers → canonical sample timeline | 不直接写 transcript | 实时线程不等待网络/磁盘慢操作 |
| PCMJournal | frames → durable chunks + checksums | 本地文件与 SQLite manifest | 先保存后识别；明确 durable watermark；崩溃恢复校验 |
| VAD/Segmenter | sample stream → speech regions | segment metadata | 不丢弃静音边界和前后文；重切片不改原音 |
| Apple adapter | PCM/time → volatile/final local candidate | Candidate Store | 离线能力按 locale/model asset 动态检查 |
| Cloud adapter | PCM chunks → provider events | Candidate Store / ModelRun | 每服务独立协议、EOS、retry、usage、consent |
| Policy Engine | network/quality/context/device state → model plan | policy trace | 仅按实测收益开关，不因“可以并行”就并行 |
| LID/Alignment | candidate + source clock → language/time spans | evidence metadata | 不伪造词级时间；置信度保留原始尺度 |
| Context Engine | app id + explicit selection/terms → scoped hints | per-record context snapshot | V1 不读屏幕/聊天；敏感字段排除 |
| Fusion Coordinator | immutable candidates → evidence-backed proposal | decisions/audit | ASR 不写正式稿和派发账本 |
| Audio Review | selected disputed audio → new candidate | ModelRun/Candidate | 盲听优先；不能将文本 LLM 当听觉模型 |
| Transcript Store | accepted proposal → version graph | SQLite | raw/formatted/user edit 独立版本 |
| Direct Input | stable prefix + target binding → UTF-16 ledger | SQLite | 至多一次自动尝试，不承诺跨应用恰好一次 |
| Recovery | incomplete jobs + journal → resumed work | queue state | 断网不阻塞录音；鉴权失败不无限重试 |

统一 Candidate 协议至少包含：recordingID、audioEpoch、generation、provider、model、configurationID、requestID、sourceSampleRange、sequence、language spans、text、isFinal、word/segment timing（可选）、raw confidence（可选）、createdAt、failure state、audio digest。供应商原始 payload 只保留经脱敏且有必要的字段。

## 5. 语言和混说识别策略

不做整句“中文/英文二选一”。先使用主多语言流的 token 语言标签；再以脚本特征、用户提示、声学边界和专家输出做时间片段级判断。中文句子里的英文技术名词通常不应切成独立语言句；需要把同一音频范围的多种候选进行证据比较。

第一层：Soniox v6 或经实测更好的统一多语言模型负责低延迟主流。
第二层：Qwen/Assembly/Meta 只在特定区间、语言、风险或模型分歧时作为挑战者；当前供应商协议若不能精确发片段，则送含前后文的滑动窗口，并把覆盖范围记录清楚。
第三层：只有冲突且影响意义时，才调用文本 LLM 选择候选引用；没有足够候选时请求音频模型复听。不能按文本“合理程度”猜词。
第四层：疑难仍 unresolved，保留备选与原音，不发布争议片段。

语言标签可能在 partial 阶段修订；所有路由决定允许撤销。用户不能感知到模型切换操作，也不需手动切换语言。

## 6. 本地与云端策略

- 正常在线且授权：本地 Apple 轻量基线可持续或按资源预算运行；云端主模型工作。是否常驻本地影子流通过 M5 实测决定，不强制。
- 网络不可用：PCMJournal 继续；Apple SpeechAnalyzer 在支持的语言/资源条件下接手或继续；云端任务排队等待网络恢复。没有本地可用语言模型时仍保存原音，状态明确为待识别。
- 网络恢复：对未完成音频按幂等任务补传/重试，校验 recording digest 与授权状态；不重复生成输入动作。
- 电池/热负载高：暂停非必要本地 shadow 和额外专家，优先保证 capture/journal 与一个识别主路。
- 质量模式：最高质量只对高风险/疑难范围增加 challenger 与复听；快速模式缩短确认路径，但不降低关键语义保护。

## 7. M5 24GB 的本地模型准入

Apple SpeechAnalyzer 是第一候选，因为系统管理模型资产、异步处理和时间戳，并不意味着它在所有语言上准确率最佳。

Qwen3-ASR-0.6B 可作为第二候选。官方公开 streaming 依赖 vLLM；需确认 macOS Apple Silicon 推理后端能否稳定实时流式，不能把官方 Linux/vLLM benchmark 当 Mac 性能。Qwen3-ASR-1.7B、ForcedAligner 0.6B 先按需批量/定稿测试，不常驻。WhisperKit/whisper.cpp/Parakeet 只有在中文+英语混说、热负载和实时因子实测胜出才纳入。

准入门槛：连续 60 分钟无丢帧；RTF p95 < 0.8；启动至首个 provisional < 1.5s；峰值 RSS 增量、CPU/GPU/ANE、温度和电量记录；在现有语料同音频配对下，CER/WER/MER 与关键实体/数字/否定错误至少不劣于 Apple baseline，且具备明确的断网价值。具体阈值为 Saytile 工程门槛，需用设备实测校准。

## 8. 上下文与个性化边界

V1 最小上下文：
- 前台应用 bundle ID / app category。
- 用户主动选中的文本（仅当用户明确开启并授权）。
- 用户手工添加的本次话题/术语。
- Saytile 自己已保存的会话内上下文。

不默认读取屏幕截图、网页 DOM、聊天历史、剪贴板全文或其他应用全部文本。上下文快照与录音关联、可查看和删除，敏感字段默认排除。上下文缺失不得阻塞首显。

词汇处理：
- Global dictionary：用户主动添加的术语。
- Session hints：本次任务临时上下文。
- Correction events：raw 与用户明确确认的改稿差异。
- Learned vocabulary：V3 才能从多次明确确认的修正形成，提供查看/撤销。
- 不把模型猜测、自动格式化或未确认改稿写入词库。

## 9. 版本保护和表达修正

每个 recording 保留 raw ASR、evidence-selected transcript、formatted view、user-edited view。所有派发以用户选择的可派发版本为准。Backtrack 仅可修改当前尚未派发区间；如用户说“刚才 SQLite 改成 PostgreSQL”，必须先识别为明确自我修正且确认时间/语义范围，不能误删已经输入目标应用的文字。模糊修正只作为新增文本或待确认事件。

## 10. 可靠性、隐私与验收

- 采集、原音、ASR、融合、文本版本和派发是独立 actor/service。
- 原音先落盘，识别可重复；候选可丢弃重建，原音不能因候选失败删除。
- API Key 只在 Keychain；每 provider 单独授权音频/文本/上下文。
- 本地文件加密与备份策略需单独评估；默认手动删除，提供空间提醒。
- 断网演练：拔网 30 分钟仍采集、落盘、可回放；网络恢复后任务恢复且不重复输入。
- 24 小时 soak：无内存增长、队列失控、录音停摆；磁盘满、权限撤销、设备切换、睡眠唤醒分别验证。
- 真实云服务对照未获用户授权时不运行收费请求。不得把协议测试或 CI 当作识别质量证明。
