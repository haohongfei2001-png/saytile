# BYOK 设置与真实语音质量验收

适用：本分支的多模型工程候选，源码核对日期 **2026-11-06**。生产 Saytile V1 RC1 与本次候选分开保留；最终构建、Mac 与 CI 验证状态见 [本轮交付记录](REVISION-2026-11-06.md)。本文提供当前实际存在的设置和定向回放流程，不建立新的公共排行榜。

**本轮没有可用的真实云端凭据，没有执行实际付费模型调用。** 协议 fixture、数据库、协调器与原生集成验证不能替代识别质量验收。下面的回放命令会使用你明确启用的服务，可能产生真实费用；应在你已授权这次音频处理并接受相应服务账单后运行。

## 1. 在原生界面配置服务

从菜单栏 Saytile 菜单进入 **「设置…」→「AI 识别」**，或从输入板的设置按钮进入；档案窗口也有「设置与存储」入口。

1. 展开「服务与 API Key」，逐项打开要使用的模型设置。
2. 确认「使用此模型」、职责、服务、模型 ID、地域与其他必需字段。
3. 在 SecureField 填入该项的 API Key，点击「保存密钥」。保存后输入框清空，不把 Key 当作普通设置保存。
4. 为这项服务开启对应的处理授权。文本融合的授权是「允许此服务处理候选文字与当前话题」；语音模型的授权是「允许此服务处理语音和必要上下文（含恢复与复核）」。
5. 选择「输入确认」模式，按需填写话题或术语提示，再开启「启用高质量云端识别」。
6. 点击「保存并应用识别设置」，确认界面成功提示。只保存 Key 不等于已经应用整套识别配置。

当前保存检查要求启用项至少包含一位中文专家和一位英文专家，每一项启用服务均有有效配置、独立处理授权和对应 Key。暂时没有某项服务的 Key 时，应明确关闭该模型或先完成配置。切换服务或职责会清除该项授权，需要重新确认；切换服务还会清空模型 ID。移除密钥会触发现有云端运行的停止/配置更新，不会删除原音。

关闭云端总开关后，普通录音路径继续使用本机 Apple 识别。云端配置仍可保留供以后使用，不需要每次讲话前选择中文或英文。[实现：原生设置](../../Sources/SaytileApp/RecognitionSettingsView.swift)、[应用配置检查](../../Sources/SaytileApp/AppModel.swift)、[识别会话工厂](../../Sources/SaytileKit/RecognitionAudioFanout.swift)。

### 当前初始模型配置

“预选启用”指模型行的 `enabled` 初始值。**云端总开关初始为关闭，所有逐服务授权初始为关闭，也没有预置 API Key。** 预选模型不会自行联网。

| 职责 | 服务 / 模型 ID | 初始状态 |
|---|---|---|
| 中文专家 | 阿里云 Qwen / `qwen-audio-3.1-asr-flash-message` | 预选启用；北京；Workspace 待填写 |
| 英文专家 | AssemblyAI / `universal-3-6-pro` | 预选启用；global |
| AI 精确融合 | OpenAI Responses / `gpt-6-astra` | 预选启用；默认 high / standard |
| 疑难原音复听 | Gemini / `gemini-3.8-flash` | 预选启用 |
| 高精度定稿 | ElevenLabs 文件识别 / `scribe_v2` | 预选启用 |
| 中英混合复核 | Soniox / `stt-rt-v6` | 初始关闭，可按需并行启用 |
| 英文强挑战者 | Meta / `muse-voice-transcribe-1.0` | 初始关闭，可作对照或追加专家 |

这些是当前接入与验收基线，不是“已经实测最高准确率”的声明。Meta 的加入也不等于已证明替换 AssemblyAI 后总体更准确。用户可以添加其他受支持的模型配置；当前并非任意厂商都能按 OpenAI 兼容接口接入。ElevenLabs 文件识别可用；当前不提供其尚未满足整流完成契约的实时适配器作为可选服务。[配置真值](../../Sources/SaytileKit/RecognitionConfiguration.swift)。

### 地域、Workspace 与提示词

| 配置 | 当前约束 |
|---|---|
| Qwen Message | UI 提供北京 `cn-beijing`、新加坡 `ap-southeast-1`；填写同地域的 Workspace ID 与 Key。当前适配器只支持上述 Message 型号，不把旧 realtime、streaming 或文件协议混用。 |
| AssemblyAI | UI 提供 global、eu；适配器另支持 JSON 配置的 `us`。模型提示最多 1,750 字符，不能无限长。 |
| Soniox / Meta | 当前适配器使用 `global`；Meta 仅支持表中的精确型号。没有提供通用自定义 endpoint 输入框。 |
| 当前话题与单模型提示 | 流式请求会合并两者。Qwen 合并后的总长度上限为 400 字，包含合并时的换行；超限在应用配置时明确拒绝。 |
| Meta 提示 | 当前 Meta 适配器提供中英语言偏置，不把任意话题文字擅自当作官方 keywords 列表；不要假设每家都会按同一方式使用提示字段。 |
| 文本融合 | 当前支持 high、xhigh、max 推理强度，以及 standard / pro 模式；pro 允许更长的复核等待，并不保证必然提高准确率。 |

提示只是识别辅助信息，不能当作用户已经说过相应词语的证据。API Key 是否有该模型、地域和付费服务的权限，仍由供应商账户决定。为新服务开户、增加余额或授权账户，需要用户实际完成对应操作。[Qwen 适配器](../../Sources/SaytileKit/QwenMessageProvider.swift)、[AssemblyAI 适配器](../../Sources/SaytileKit/AssemblyStreamingProvider.swift)、[Meta 适配器](../../Sources/SaytileKit/MetaStreamingProvider.swift)。

### Keychain 与费用

Keychain 按 **服务商 + 配置 UUID** 分开保存，即使同一服务商配置两个模型，也有独立的凭据项。模型配置 JSON 不包含 Key。把 JSON 中的 `id` 随意换成新 UUID，会使该配置找不到原来保存的密钥；应保留对应行的 ID，或为新行重新保存 Key。CLI 只读取启用配置对应的 Saytile Keychain 项，不搜索环境变量或其他项目的密钥。[凭据实现](../../Sources/SaytileKit/CloudCredentials.swift)。

在「最近模型调用与用量」查看模型、状态、错误和返回的用量。「可选费用估算」可填写币种、音频/会话小时单价，以及每百万输入、输出 Token 单价；这些是用户填写费率后的估算，不是供应商结算账单。AssemblyAI 流式采用会话时长口径；其他服务的实际计费规则需要对照其账单。

**没有返回用量或未填写费率时，金额保持未知，不能填成 0。** 失败请求也可能产生费用；不同币种的估算不能直接加总。报告中的 `modelUsage` 应与运行状态、供应商账单一起检查。

## 2. 两种输入确认模式

| 模式 | 当前行为 | 验收重点 |
|---|---|---|
| 最高质量，默认 | 持续保留实时预览；等待已启用专家对相应音频提供足够证据。模型自身 final 不能绕过其他专家。分歧可进入文本仲裁与原音复听，未确认部分留在 Saytile。 | 首次文字、讲话中修订和可派发稳定文字都要评估；不能只看最后稿。追加专家可能增加等待，需证明质量收益。 |
| 快速输入 | 可较早发布符合条件的稳定前缀，不必等全部高精度复核完成。 | 后续更准确的替代版本保存在 Saytile；已提交前缀不能自动改写、重发或重复插入。 |

两种模式共享原音、候选与融合系统，区别在于确认门槛。外部直接输入仍要求明确目标绑定与校验；不会自动发送消息。最高质量模式也不能把未完成或失败的复核写成成功。

没有一个固定的“等若干秒就一定正确”的承诺。网络握手、EOS drain 和会话存活超时属于故障预算，不是准确率阈值。用户编辑稿、音频 epoch、识别代次、UTF-16 范围和派发账本仍有最终约束。[协调器](../../Sources/SaytileKit/MultiRecognitionSession.swift)、[融合规则](../../Sources/SaytileKit/RecognitionFusion.swift)、[持久化与派发](../../Sources/SaytileKit/Store.swift)。

## 3. 已保存 WAV 的同音频定向回放

### 输入与隔离要求

使用本次候选 App 的可执行文件，保留生产 RC1 安装和私人资料库。当前 CLI 必须同时指定：

- `--multi-asr-probe`：已有本地 WAV 文件。
- `--recognition-config`：显式的 `RecognitionConfiguration` JSON 文件。
- `--data-directory`：此次运行专用、没有任何录音记录的独立目录。
- `--report-dir`：报告输出目录。

输入必须是 **非空 RIFF/WAV、16,000 Hz、单声道、有符号小端 16-bit PCM**。入口不会把 MP3、48 kHz、立体声或其他编码暗中转换成合格输入。优先使用已下载、格式合适的真人样本；若确需预处理，保留原文件，把转换后的同一份 WAV 固定为所有待比较配置的输入，记录处理步骤及文件哈希。

**12 MB 限制需单独理解：**当前高精度复核保留的整段 PCM 内存快照上限是 **12,000,000 字节**，在 16 kHz 单声道 PCM16 下为 **375 秒，即 6 分 15 秒**，不含 WAV 头。超过上限后，原音持久化与流式专家仍可继续，但整段内存快照不再可用，依赖它的音频复听/文件定稿会报告未完成。当前不能宣称已实现任意长度音频的自动分段精确复核，也不会把被截短的快照冒充完整音频。用于本轮完整链路验收的单条样本应短于此边界。[音频分发与快照](../../Sources/SaytileKit/RecognitionAudioFanout.swift)、[复听限制](../../Sources/SaytileKit/PrecisionReviewClient.swift)。

### 准备显式配置 JSON

当前原生界面没有一键导出配置按钮。高级验收可以按 [配置结构](../../Sources/SaytileKit/RecognitionConfiguration.swift) 创建 JSON，逐项对照原生设置，并保留已保存 Key 的配置 UUID。文件只含设置，**不要加入 API Key**。

以下示例是当前五项预选质量配置；Soniox 与 Meta 未列入，等价于本次运行不启用它们。替换 Qwen Workspace，确认这些 UUID 对应的五项 Key 已在原生界面保存。示例的 `cloudEnabled` 与 `cloudConsent` 为 `true` 仅用于说明完成明确授权后的配置，不应在尚未授权时直接运行。

```json
{
  "cloudEnabled": true,
  "inputMode": "highestQuality",
  "topicContext": "",
  "automaticRecovery": false,
  "models": [
    {
      "id": "A71E0001-0000-4000-8000-000000000001",
      "purpose": "chineseASR", "provider": "qwenMessage",
      "model": "qwen-audio-3.1-asr-flash-message",
      "enabled": true, "cloudConsent": true,
      "region": "cn-beijing", "workspaceID": "REPLACE-WITH-YOUR-WORKSPACE",
      "context": "", "currency": "CNY",
      "reasoningEffort": "high", "reasoningMode": "standard"
    },
    {
      "id": "A71E0001-0000-4000-8000-000000000002",
      "purpose": "englishASR", "provider": "assemblyAI",
      "model": "universal-3-6-pro",
      "enabled": true, "cloudConsent": true,
      "region": "global", "workspaceID": "",
      "context": "", "currency": "USD",
      "reasoningEffort": "high", "reasoningMode": "standard"
    },
    {
      "id": "A71E0001-0000-4000-8000-000000000004",
      "purpose": "textFusion", "provider": "openAIResponses",
      "model": "gpt-6-astra",
      "enabled": true, "cloudConsent": true,
      "region": "global", "workspaceID": "",
      "context": "", "currency": "USD",
      "reasoningEffort": "high", "reasoningMode": "standard"
    },
    {
      "id": "A71E0001-0000-4000-8000-000000000005",
      "purpose": "audioReview", "provider": "gemini",
      "model": "gemini-3.8-flash",
      "enabled": true, "cloudConsent": true,
      "region": "global", "workspaceID": "",
      "context": "", "currency": "USD",
      "reasoningEffort": "high", "reasoningMode": "standard"
    },
    {
      "id": "A71E0001-0000-4000-8000-000000000006",
      "purpose": "finalASR", "provider": "elevenLabsFile",
      "model": "scribe_v2",
      "enabled": true, "cloudConsent": true,
      "region": "global", "workspaceID": "",
      "context": "", "currency": "USD",
      "reasoningEffort": "high", "reasoningMode": "standard"
    }
  ]
}
```

估算费率字段是可选项，示例没有把未知费用设成零。`automaticRecovery: false` 用于明确标记此次定向验收配置；当前 probe 入口执行一次会话，失败后由用户检查报告并决定是否重试，不启动普通录音界面的后台恢复循环。

### 执行与重复对照

下面都是本地路径占位符，应换成实际候选 App、已有 WAV 和配置文件。每一次运行使用新的空数据目录；保留前一轮目录和报告，不覆盖已有结果。

```bash
"/absolute/path/asr-preview/Saytile.app/Contents/MacOS/Saytile" \
  --multi-asr-probe "/absolute/path/samples/existing-mixed.wav" \
  --recognition-config "/absolute/path/acceptance/config-quality.json" \
  --data-directory "/absolute/path/acceptance/run-A/store" \
  --report-dir "/absolute/path/acceptance/run-A/report"
```

入口先校验格式、配置和授权，再读取明确启用的 Keychain 项。所有必需 Key 都存在后，完整 PCM 先经 `PCMJournal` 保存并登记数据库，再创建真实 `MultiRecognitionSession`，按 **20 ms、640 字节**的实际节奏向所有流式模型发送同一音频，最后发送结束并等待模型/融合完成。全程不打开麦克风、不绑定外部输入目标、不执行自动派发。[CLI 入口](../../Sources/SaytileApp/SaytileApp.swift)、[回放与报告实现](../../Sources/SaytileKit/MultiRecognitionDiagnostics.swift)。

完成后报告位于 `--report-dir/<recording-UUID>.json`，终端输出 `MULTI_ASR_PROBE_RECORDED ... state=...`。状态 `completed` 表示当前识别流程完成，**不表示逐字正确**。模型失败或未消除分歧也可保留报告和原音：CLI 在记录存在但状态不为 `completed` 时返回退出码 `2`；入口错误返回 `1`，缺少独立数据目录参数返回 `64`。不要只凭命令有 JSON 输出就计为质量通过。

对同一份 WAV 比较最高质量/快速模式时，只修改 `inputMode` 为 `highestQuality` / `fast`，保留模型、话题、音频和其他设置，并使用不同运行目录。对照某个额外专家或复核模型时，再单独修改对应项，避免同时改变多项后无法解释收益。每一轮真实调用可能再次计费；本轮没有执行这些示例命令。

## 4. 如何阅读证据，而不是只看最终文本

JSON 包含 `recording`、`replay`、`timing`、`candidates`、`fusionDecisions`、`modelRuns`、`modelUsage`、`revisions` 和 `dispatchableRevision`。候选保留模型、录音/识别代次、序列、原文、稳定 UTF-16 长度及真实时间。日期使用 Unix epoch 毫秒；不存在的值保持缺失，不补零。

| 阶段 | 对照证据 | 必须补做的质量判断 |
|---|---|---|
| 首次实时文字 | 最早非空候选及预览；`firstCandidateSeconds`、`firstPreviewSeconds` | 同一已听音频范围内的错字、漏字、幻觉、术语与否定/数字是否正确；不能拿很短的首字与整句真值混算。 |
| 讲话中修订 | 按 `createdAt` / sequence 重建候选和融合预览变化 | 使用一致的已输入音频进度检查错误率、修正速度、错误持续时间与反复改动；不能只截取最好的一帧。 |
| 可输入外部应用的稳定文字 | outcome 为 `published` 的融合决策、`firstStableSeconds`、稳定范围、`dispatchableRevision` | 对稳定前缀逐字评分，检查否定、金额、时间、单位、重复与中英术语；同时记录等待时长和未提交覆盖率。probe 不实际验证外部应用插入。 |
| 完整音频与高精度复核后的版本 | 完整候选、音频复听/文件定稿运行、最终版本、逻辑状态与结束时间 | 真人复听并对照参考稿，确认所有启用的必要复核实际成功；内部更准确替代稿与已派发 head 应分别记录。 |

`firstPreview` 是融合预览持久化时间，不是屏幕真正绘制的时间；稳定发布表示具备派发资格，不是外部应用已经收到。某一家 `isComplete` 也不等于统一定稿。报告明确写入 `accuracyMeasurement: "not-measured-no-reference-transcript"`，不会自动生成准确率。

## 5. 最小真人验收集与通过条件

继续复用已经保存的真人语音、参考稿和本地样本。优先抽取最能改变裁决的少量片段：自然中文、自然英文、中英句内切换、SwiftUI/SQLite/ChatGPT 类术语、否定、金额与单位、时间、故意重复、弱音/噪声和片头静音。参考稿应由人听原音确认，不能让待评模型自己的输出充当真值。

在四个阶段分别报告中文 CER、英文 WER、明确分词/归一化约定的混合 MER，并单列关键内容错误。严格忠实度评分必须保留否定、数字、单位和有意重复；标点/大小写的宽松评分可以另列，不能替换严格结果。短定向样本只能支持其覆盖范围内的判断；统计不足时明确不确定，不能据很小的差值宣布普遍胜出。

验收至少应回答：

- 新增专家或 AI 是否在同一音频上修正了实际错误，是否同时引入新错误？
- 改善是否出现在讲话中与稳定前缀，而不仅是最终复核版本？
- 困难片段是否正确保留不确定性，且没有因常识或术语提示改变原话？
- 模型失败后原音、其他候选和恢复资格是否仍在；迟到结果是否受代次校验？
- 快速模式已提交内容被后续版本否定时，替代版本是否只留在 Saytile，派发 head 是否保持不变？
- 所有预期运行是否有状态和用量记录，未知费用是否仍显示未知？

已有 **112 条真人音频 × Apple 固定中文、Apple 已知语言、本地 Qwen3-ASR 三种配置，共 336 条输出**继续作为历史证据；它们不是 336 条独立录音，也不是本轮最新云模型成绩。已有 Apple paced 回放同样保留，不重新下载和重做整套测试。公开/本地证据缺口由上面的少量针对性云端回放填补，而不是重建一个大排行榜。[历史本地证据](results/LOCAL_EVIDENCE.md)、[已有 paced 结果](results/paced/README.md)。

**发布质量结论的门槛：完成得到授权的同音频真实云端运行，并对四阶段证据进行人工真值评分。** 在此之前，应准确表述为“多模型工程候选与验收入口已实现”，不能表述为“最高识别准确率已经验证”。


---

## 2026-11-07 模型调度与混合架构补充

现有设置 UI 的多服务 BYOK 能力保留，但“已配置/已启用”不应等同于“每次录音必然调用”。下一版设置需区分：

- 可用模型（已保存配置和 Key）；
- 用户授权范围（音频、候选文本、上下文分别授权）；
- 质量策略（主路、按需 challenger、原音复听、文件定稿）；
- 本次录音的实际模型计划与实际调用账本。

Soniox STT v6 新增进入同音频对照，不自动覆盖当前推荐配置。必须核验实际服务端模型 ID、地域、语言 token、EOS/finished 语义、断连恢复、限流和计费。v5 benchmark 不可移植到 v6。

离线能力不得以“云端开关关闭后旧 Apple 路径仍工作”作为充分验收。必须验证 Apple 与云候选进入统一 Store；网络断开后采集持续、原音落盘、可用本地模型继续转写；网络恢复后恢复待识别任务且不重复派发。

质量验收至少包含主多语言模型、Apple 本地 baseline、Qwen/Assembly/Meta challenger 的同音频配对。先使用既有 112 条音频中的 24 条代表性片段，不扩充下载，不将私人音频上传到未经授权的服务。真实云请求仍须有用户明确授权和预算。
