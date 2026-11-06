# 交给 Codex：Soniox 单引擎接入实施要求

**执行依据：2026-11-06 [DECISION.md](DECISION.md)。只实现 Soniox `stt-rt-v6` 云端主路径，保留 Apple 本地备用。** 本文是后续实现 PR 的规范，当前研究 PR 不修改 RC1。先读仓库 `AGENTS.md` 与现有数据契约；以重新确认的最新 `main` 开独立实现分支，禁止在个人录音数据库上做迁移试验。

## 1. 产品与代码边界

无需重新实现录音、档案、编辑、搜索、复制或目标输入。保留 `PCMJournal`、`SaytileStore`、`NativeInputCoordinator`，在它们之间加入一个小型引擎适配层。只需 Apple 与 Soniox 两个实现，不创建五供应商框架，不添加自动二次定稿、投票、自动润色、翻译或个人词库系统。

| 现有位置 | 必要改动 |
|---|---|
| `Sources/SaytileKit/SpeechRecognition.swift` | 把当前 Apple session 包装成同一小接口；locale 成为明确设置；新增独立 Soniox transport / accumulator。 |
| `AudioCapture.swift` | 保持采集、重采样与先写 journal；按引擎配置逻辑会话边界；识别结束异步 drain，不在收音循环等待网络。 |
| `AudioJournal.swift` | 将 VAD 结束静音与最大活动帧参数化；Apple 默认保持原值，云模式使用下述规则；15 秒 WAV 轮转不变。 |
| `Store.swift` | 延续每 recording 一个 active attempt。无需多引擎 schema；只增加必要的 provider/model/region/run 元数据，避免修改旧 revision 文本。 |
| `InputCoordinator.swift` / 绑定调用处 | 继续稳定 UTF-16 后缀派发、绑定验证、迟到保护；长录音期间重新绑定时形成明确的新逻辑录音边界。 |
| 设置与状态展示 | 明确本地/云端、项目地域、连接失败与本地备用状态；原音与文字保存语义不变。 |

## 2. 最小 Swift 接口与唯一发布权

接口可以按现有代码风格实现，不要求照搬研究命名。一个 session 绑定一个现有 `RecognitionTicket`，由 coordinator 独占调用 Store；adapter 自身不创建第二张 ticket。

```swift
struct RecognitionSnapshot: Sendable {
    let runID: UUID
    let sequence: UInt64
    let stableText: String       // provider 已确认的整个连续前缀
    let displayText: String      // stableText + 最新可变尾部
}

enum RecognitionEvent: Sendable {
    case snapshot(RecognitionSnapshot)
    case completed
    case failed(code: String, retryable: Bool)
}

protocol StreamingRecognitionSession: Sendable {
    var events: AsyncThrowingStream<RecognitionEvent, Error> { get }
    // 本地有界入队；不能等待网络发完，溢出需显式返回失败。
    func offerPCM(_ pcm: Data, sourceStartFrame: Int64) -> Bool
    // 只关闭输入并启动异步 drain；不能同步等待 provider final。
    func finishInput()
    func cancel()
}
```

源时钟以重采样后的采集流按 16 kHz 持续计数，待机预卷也带源样本索引；每条 recording 另存它的起点与已接纳范围。不能用墙上时钟推断音频范围。coordinator 另外持有 recording ID、ticket ID、audio epoch、连接 run ID；过期 run 或 epoch 的事件直接拒绝。

发布策略沿用 Apple 现有流程：稳定前缀变长时 `applyRecognition(..., text: stableText, isFinal: true)`；展示尾部变化时发布 `isFinal: false` 的完整预览。只有真正收到正常结束、所有尾部已确认后才 `finishRecognition`。若只收到部分 final，保留它，但把尝试记为失败/可恢复，不能伪造完整定稿。

`benchmark/ASRInterfaces.swift` 是早期研究接口草图，包含未采用的多阶段扩展；**不是本次必须实现的框架**。生产按上面的最小接口收敛。

## 3. Soniox 的确切接入

官方入口：[WebSocket API](https://docs.soniox.com/api-reference/stt/websocket-api)、[实时结果语义](https://docs.soniox.com/stt/rt/real-time-transcription)、[SDK 列表](https://docs.soniox.com/sdk)。官方 SDK 没有 Swift 项，因此使用系统 `URLSessionWebSocketTask` 包装正式协议；无需在 Mac App 内嵌 Python、Pipecat 或 Node。

以授权项目的地域端点为准。美国端点是 `wss://stt-rt.soniox.com/transcribe-websocket`；区域项目使用其匹配域名与密钥，不能擅自用日本域名配美国项目。握手 `URLRequest` 设置 `Authorization: Bearer <credential>`。不要把长期 key 放进启动 JSON；旧 `api_key` 字段已经弃用。

启动文本 JSON：

```json
{
  "model": "stt-rt-v6",
  "audio_format": "pcm_s16le",
  "sample_rate": 16000,
  "num_channels": 1,
  "language_hints": ["zh", "en"],
  "language_hints_strict": false,
  "enable_speaker_diarization": false,
  "enable_language_identification": true,
  "enable_endpoint_detection": true,
  "endpoint_latency_adjustment_level": 0,
  "endpoint_sensitivity": 0.0,
  "max_endpoint_delay_ms": 2000
}
```

随后的音频消息是二进制 **PCM payload**，不逐帧添加 WAV header、不 base64 化、不把 16 kHz 伪标为其他采样率。复用现有持续运行的 `AVAudioConverter`；已有 20 ms / 640 byte 帧可顺序合并为 40–100 ms 发送批次，保留每批源样本范围，不额外等待凑满尾批。连接和发送在独立 task 中进行。

`language_hints` 是偏好而不是强制单语判定。保持中英原文；不设置 translation。context 只允许有限、明确授权的产品/领域词拼写，不塞参考答案、私人档案或猜测的数字；首版可不传 context，不以此启动 V3 个人词库工程。[语言提示](https://docs.soniox.com/stt/concepts/language-hints) / [context](https://docs.soniox.com/stt/concepts/context)。

## 4. 文字累积与正式结束

Soniox 单独维护两个缓冲：`confirmedTokens` 与 `draftTokens`。一条响应中的新 final tokens 按顺序加入 confirmed；该响应的 non-final tokens 整体替换之前 draft。展示为两者连接。**绝不能把每次 partial 全文追加。** final token 不需要再次按字符串去重；“不不不”“非常非常”等可能是合法原话，不能被启发式删掉。

- 单连接只设一个接收 loop，消息按顺序处理。local sequence 是本地顺序戳，不能假装服务端有未提供的 token ID。
- 过滤协议特殊标记 `<end>`、`<fin>`，不输入用户文本。它们是稳定/控制事件，不代表“发送消息”或按回车。
- provider final 代表停止修订，并不代表事实正确；不把 confidence 当作经过校准的语义正确率。
- `<end>` 可结束一个文字片段，但不必关闭同一个正在连续录音的 WS。
- `finishInput()` 拒绝新音频，把 EOS 放在**同一个串行发送队列的末尾**；所有已接纳 PCM 和不足一批的尾包发送成功后，才能发送 **空 TEXT 帧** `.string("")`。不得由控制 task 越过未发送音频发 EOS。空 binary `.data(Data())` 不是等价结束方式。继续接收，直到 `finished: true`；再关闭连接。
- `finished` 或正常 WS close 没有正确收到时，记录为未完整结束；已保存音频与已确认文字继续保留。

采用 [官方 endpoint 默认值](https://docs.soniox.com/stt/rt/endpoint-detection)。不要直接复制语音对话代理的激进低延迟参数。首版正常停录用空文本 EOS，不按每次 VAD 静音发送 `finalize`。以后若需要保持连接但强制定稿，遵循 [manual finalization](https://docs.soniox.com/stt/rt/manual-finalization)：约 200 ms 静音后发送控制消息，等待 `<fin>`；不能把发送控制消息当作已经定稿。

## 5. 最少改动的录音与连接生命周期

**一条逻辑 recording = 一张 ticket = 一个 Soniox WS。** 不引入跨 recording token 时间归属，不把一个新结果流拆分到多个旧录音。

云端模式的 `VoiceSegmenter` 保留 WebRTC mode 2、20 ms 帧、3-vote 起始和 1 秒预卷；取消 1,500 帧强制结束，结束静音先设 **100 帧 / 2.0 秒**。这是资源回收的工程初值，未被本轮实验优化；已确认文字可以更早显示和派发，不必等 2 秒。Apple 备用先保留 40 帧 / 800 ms 与原有最长段策略，避免顺带改变稳定本地路径。

长句继续写同一个 recording 的多份 15 秒 journal 文件，不在文件轮转时重置云模型。provider 语义 endpoint 可以在其中多次确认文字；本地进入足够长静音、用户暂停、设备中断、明确的目标重绑定或服务时限到达，才结束逻辑 recording。

结束顺序：

1. 收音循环排空 ring，适用时 drain converter；完整 PCM 先落 journal。保持现有 checkpoint / durableFrames 规则。
2. 关闭并登记当前 journal，`finishRecording` 只结束音频状态。
3. 对识别 session `finishInput()`，把它交给独立 drain task；**`CaptureWorker.endUtterance()` 不 await 网络 `finished`**。
4. 新讲话立即建立新的 recording / ticket / WS，旧录音的 ticket 直到自身 drain 完成仍有效。
5. provider 正常完成才 `finishRecognition`；超时或失败则保存可恢复状态。新录音已派发后，旧录音晚到结果继续遵守 `lateRecognitionDeferred`，留在输入板，不补插到错误位置。

音频结束与识别结束分开，不能因为网络慢而停读 ring。也不能因为已有两个较新段，就执行旧 `retired > 2` 的任意取消策略。

### 目标重新绑定边界

现有 `Store.createBinding` 以已存在 recording 的水位屏蔽绑定前语音。取消 30 秒切段后，重新绑定不能仍无限沿用旧 recording。绑定协调器先撤销旧派发权，要求 capture 在下一个完整 PCM 边界结束旧逻辑录音，再创建新 binding，随后创建新的 recording。该本地边界不等待云端完成；必要的几个 PCM 帧留在有界缓冲。

严格保持源样本一次归属：旧段最后一个样本之后才是新段第一个样本，强制边界不再次重放旧段的 1 秒预卷。绑定前的旧录音与旧 final 永远不能获得新目标的派发资格。仅取消目标绑定无需切断录音。实现时用已有隔离目标 fixture 检查这一竞态。

即使处于待机，新 binding 也必须设置 `captureSampleIndex` cutoff，清除或隔离 cutoff 之前的 pre-roll、pending 及旧起始票数，防止旧声音随后借新 recording 的 rowid 获得派发权。绑定创建期间只暂停逻辑 recording 的接纳，原始采集继续进入有界缓冲；以 generation 与 cutoff 保证边界、binding 和新 recording 的顺序。目标验证失败时，缓冲只能按原音保存/本地预览策略处理，不能获得新的派发资格。

## 6. 有界运行、失败与恢复

以下是首版工程边界，**不是供应商实测性能**；在接入验证中只为明确故障修正，禁止无限重试：

| 项目 | 初始策略 |
|---|---|
| 每 session 未发送音频 | 最多 6 秒 / 192,000 byte PCM；溢出立即将本次识别标为可恢复失败，录音独立继续。 |
| 握手超时 | 10 秒；不得阻塞原音保存。 |
| 输入结束后 drain | 最多 20 秒；将超时与模型返回空文字区分。 |
| 同时云会话 | 最多 3 个，含 active 与 draining；预算满时新录音仅保存、排队，不淘汰已接纳旧 final。 |
| 后台恢复 | 单独使用同引擎；初始实时请求之后最多 2 次自动恢复认领，跨进程重启持续计数，退避并受总预算限制。 |
| 鉴权/权限/余额 | 401/403/402 不循环重试，不自动充值或开通服务。清楚显示可恢复原因。 |
| WS 服务时限 | 每个 stream 最多 300 分钟**音频**，按累计发送样本计数，不是建立连接后的墙钟时长；提前结束逻辑录音并保存边界状态。超长无停顿超过支持边界时显式降级/排队。 |

若连接暂时保持但没有音频，按 [keepalive](https://docs.soniox.com/stt/rt/connection-keepalive) 发送控制消息；不要靠空 TEXT 保活，那会结束音频。上述每逻辑录音关闭策略不需要全天挂着一个计费空闲会话。[服务限制](https://docs.soniox.com/stt/rt/limits-and-quotas)。

恢复优先复用已保存原音，取得现有 audio lease 并核验 audio epoch。用新 attempt / run 重新识别整段，不把旧连接的 draft 串到新连接后面。首版不实现复杂的跨连接重叠流重建；先把失败 recording 保留为可重试，后续新 recording 可以采用已就绪的 Apple 本地备用。切换须显示引擎状态，不能把 Apple 结果标成 Soniox。

`retryable: false` 必须落实到持久化恢复资格与实际 `claimRecoveryRecording` 筛选。现有恢复机制会认领 queued/failed，默认最多 3 次自动认领；不能只改 adapter 的枚举或 UI。云模式明确限制为上述 2 次自动恢复，过滤鉴权/余额/权限错误；凭据修复后可通过明确操作重新排队。Apple 既有调度不顺带改写。

重新识别结果保存为新的不可变版本。已派发过文字时，仍走现有前缀一致性与顺序检查；前缀不同、投递不确定或目标已变就停止自动追加，绝不删目标文字、重发全文或重试不确定投递。用户编辑继续优先，不被晚到 ASR 覆盖。删除原音使 epoch 失效并取消依赖任务，保留文字；App 重启失效旧输入绑定。

整段重试的初期 stableText 常短于已派发游标，这不是前缀改变。重试 attempt 先处于自动追加暂停状态；只有 confirmed 文本覆盖已有 UTF-16 游标且覆盖部分逐字一致，才允许新增后缀进入 `reserveDispatch`。未覆盖时等待，确认不一致时保存新版本并停止该绑定自动追加。所有自动派发入口都必须遵守该状态，不能只改显示层；否则现有 `prefixChanged` 会把正常的重试追赶误判为冲突。不得改写历史派发记录或跳过目标/顺序校验。

## 7. 密钥、地域与最少产品设置

个人开发/自用版本只使用用户已有且授权的服务凭据，通过 macOS Keychain 保存，例如独立 service `com.saytile.asr.soniox`；项目地域与 host 显式配对。不得放入源码、UserDefaults、包资源、日志、崩溃报告或研究结果。记录请求 ID、model、run、音频 hash、地区与耗时即可，不记录 Authorization、完整配置中的秘密或签名 URL。

面向分发的商业版本不能打包共享长期 key。届时使用服务端签发的短期凭据或代理；**本次不为了一个自用接入先建设收费后端**。云端处理需明确启用；没有凭据、离线或拒绝云处理时保留 Apple，不能静默上传。

官方 [地域说明](https://docs.soniox.com/data-residency) 没有大陆端点承诺。选择已授权项目对应域名；不得自行申请付费地域、新服务、充值或把私人录音用于公共演示。此次开发与验收只用既有合法公共片段。未来接入 Qwen 需独立的同地区 Workspace / ASR 权限，已有聊天模型账号不等于已具备此权限。

## 8. 只做会影响发布的验证

### 不需要云密钥即可完成

使用协议 fixture 与现有隔离测试设施，检查以下真实风险：

1. 多次 partial 改写、final 后跟新 draft、重复合法词、UTF-16 边界、`<end>/<fin>`、空文本 EOS 与 `finished`；最终文本和派发后缀一致且只一次。
2. 日志 15 秒轮转与连续超过 30 秒不导致新云会话；活动短尾保留。重绑定边界 PCM 不重叠不丢失。
3. 慢 drain、新话进入、连接预算满、网络断开、超时与旧结果乱序，均不阻塞 journal；最终状态可恢复。
4. 删除音频、用户编辑、重启、目标变化、不确定投递与迟到结果，继续通过现有 Store / InputCoordinator 合同测试。

不要为每个 getter 或字面配置写镜像测试；不要重跑无关 GUI 验收。音频/VAD 的旧合成测试不能替代供应商协议验证，三次研究 probe 也不能代替完整集成回放。

### 具备已授权凭据后的唯一小范围真连接验收

使用旧研究已存在的 `research/asr-2026-11-06/corpus/latency-manifest.json` 的 12 条，必要时从同一冻结 manifest 补已有关键难例，最多 **20 条独立片段 / 总上传 15 分钟（含 direct、生产路径与全部重试）**。不下载新大语料，不要求用户现在录音，不同时调用其他厂商。

- 相同 PCM 分别直接送 adapter、走实际 CaptureWorker/coordinator 的回放注入点；不得把研究 VoiceSegmenter-only probe 当作完整路径。保留音频 hash、型号、设置、请求 ID、文本与事件时序。完成 sample budget 后停止。
- 核查中文、英文、自然混说、术语、数字、否定与连续表达的已有具体例子。对参考文字疑点先核对上游标注/原音，不用语言模型猜 gold。逐例报告新增/修复错误，不把 20 条称为可靠全球排名。
- 对数字、否定或漏词的明确新增错误必须解释并处理；平均 CER 改善不能掩盖关键意义反转。不启用自动纠错来隐藏原始 ASR 错误。
- 实时按音频节奏喂入，分别记录首预览、首稳定前缀、最后真实语音结束至最后定稿；记录 cold/warm 和地区。不用文件处理倍速或 EOF 后耗时替代用户感知延迟。
- 初始发布目标：预热首预览不超过约 1.5 秒，停声后稳定定稿不超过约 2 秒；逐条列出异常与样本最大值。此为产品目标，**不是已有实测保证**；如此小样本的 P95 不能声称是总体尾延迟。出现重复输入、未保存原音、静音幻觉或未解释关键意义反转时不切生产默认。
- 校验 0 重复/漏派发、0 journal 丢样、完整 final/可恢复失败的状态区分。测试只能写独立 fixture 资料与专用目标框，不动用户草稿或个人数据库。

若缺少密钥，完成所有无密钥实现与测试，在 PR 中准确标出真连接验收未执行，不编造云成绩、不要求用户现场讲话。若实际网络不达标，按 DECISION 的唯一条件备选转向 Qwen Audio 3.1 Message；并在改接前核对其最终事件语义，不把可修订结果猜成稳定前缀。

## 9. 提交顺序与 Codex 完成标准

1. **适配层提交**：抽出最小 session，Apple 原行为回归，新增 locale 设置与必要引擎元数据。
2. **Soniox 提交**：正式 WS 协议、final/draft 累积、Keychain、状态显示、有限故障恢复；fixture 验证。
3. **连续表达提交**：云端边界参数、异步 drain、容量处理、目标重绑定边界；真实生产调用路径的定向回归。
4. **候选验收提交**：有凭据时完成上述有限真连接验收；准确报告未测内容、延迟与关键样例。无凭据则交付可检验实现与明确剩余门槛。
5. **独立候选包 / 实现 PR**：保持已安装 RC1 和其数据可用；未经上述门槛，不修改正式默认、不合并未经验证的模型替换。

交付应回答“接入了什么、为何改善当前缺陷、如何验证、还有什么未验证”，不再回到建立新排行榜、扩充大量语料或自动双模型系统。
