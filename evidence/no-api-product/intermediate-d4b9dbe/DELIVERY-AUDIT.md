> 根代理后续核对：30分钟文件/数据库验收通过后，额外隔离检查输入与已保存时长相差92.875毫秒的来源；当前尚未证实讲话被截断，也尚未以根因解释排除。下方独立审计建议保持原记录，最终交付裁决待这项有界检查完成。

# 最终交付有界审计 — d4b9dbe

审计范围：用户最新《无 API 条件下完成完整产品开发：最终凭据接入即可启用》要求、当前冻结源码的关键入口，以及本目录最终证据。只读审查源码和已有结果，未重复测试、调用真实服务或访问用户数据。

**最终结论：冻结源码的已计划无 API 工程验收现已完成，包括 30 分钟墙钟采集及事后持久化核对；证据支持 `NO_API_ENGINEERING_READY`，同时保持 `LIVE_CONNECTION_PENDING`。** 本结论保留下文全部验证边界，不支持 `LIVE_PROTOCOL_VERIFIED`、`LIVE_TRANSCRIPTION_VERIFIED`、`QUALITY_VERIFIED` 或 `PRODUCTION_READY`。最终证据由根代理统一提交 PR #6。

本次审计未发现新的确证 P0/P1，也未找到一个仍须新增核心功能、却能在无 API 条件下独立完成的具体遗漏。此结论有界：不等于证明所有外部应用兼容、真实人声质量或未知历史安全信号已解释。

## 来源与安装包一致性

- 运行时提交：`d4b9dbe812b9084f1bf31c1817c7b67095e17fc7`；tree：`01f8644b57935f7f9beb9759ad3e8f44dda2ce30`。
- 本地完整网络/原生套件：**378 个测试方法、45 个套件、495 个展开场景**。其中实际 localhost 网络为 50 个 case，协议违约为零。AppModel 为 **66 项**。不是将这些不同层级计数相加为一个“产品通过率”。
- CI 两流程成功，测试的是合并提交 `5dd66d8c3a8bd58bf8cad21289c9f875fdbd3883`，其 tree 与上述 HEAD 相同；没有把两个 commit ID 混称为同一个 SHA。CI 日志哈希复核相符。CI 的原生 UI 只有渲染，真实控件操作来自本机最终 UI 证据。
- protocol、input、local、package 四组来源清单交集中的 **197 个运行时/测试/脚本文件哈希全部一致**；protocol 另计 workflow/packaging 文件，共 201 个，并无计数冲突。
- 实际 `dist/Saytile.app` 可执行文件哈希为 `b07cabe2473e23f5f082c38e95231ec8ad49bb5449d14d0dfbefe21a83447e30`；DMG 为 `ae9fb8b9c716b4b4586c033aa5c7b667c1d3493617b849083387fba929ab5cc5`。本次重新读取实物并计算哈希，均匹配 receipt。
- Info.plist 标识 `1.0.0-rc.2-no-api.2`、上述源码、未脏构建、菜单栏应用、macOS 26.0 最低版本；二进制为 arm64。UI、安装升级、卸载重装、设置 CLI receipt 均绑定同一可执行文件。
- 最终 22 张 UI 图像哈希全部相符。实际查看了首次检查费用页面和紧凑档案页面：费用范围、服务授权、历史录音保护说明可见；修改稿、原音已删除、不可用动作等状态相互一致。

## 按用户要求核对

| 要求 | 当前证据与判断 | 不应扩大为 |
| --- | --- | --- |
| Qwen、Assembly、GPT 的正式适配器 | 既有官方协议审计；`protocol/README.md`、完整 URLSession 网络套件、wire audit；真实客户端发送完整 PCM、接收 partial/final、关闭并处理失败 | 真实供应商鉴权或现网协议已通过 |
| 真正的离线服务模拟器 | 生产网络客户端与 stateful localhost WS/HTTP 对接；相同 PCM 字节和哈希、乱序/断线/取消/配额/坏包/缺 final、GPT 持久会话与 HTTP fallback 均有当前来源结果 | 固定模拟输出具有真实 ASR 准确率 |
| 唯一持续文字、修正、EOS | 生产 transcript engine→Store 的三次可见文字变化、GPT 证据校验和最终状态；不支持的证据不能成为可派发最终稿；完整套件覆盖用户编辑和迟到结果 | 真人说话时的舒适度、实际云端延迟或融合收益已证明 |
| 首次三服务消费者流程 | `ui/manifest.json`：22 图、34 AXPress、6 AXSetValue、6 次原生字段提交（含 3 SecureField）、9 组交互。实际填写三 key/Workspace、三个服务授权和费用授权，并检查成功、失败、取消状态 | “已接通”截图代表真实服务；成功 receipt 是醒目标注的 TEST_ONLY 注入 |
| 凭据保存与授权 | 真实 Security.framework 独立随机测试 namespace 的创建/替换/读取/删除；66 AppModel 检查覆盖异步配置、撤权、代际和退出。默认真实路径只将密钥存于 Keychain | 注入 UI 已独立证明生产账户中的真实密钥和访问控制可用 |
| 最后填 key 后即可运行检查 | `AppModel.checkRecognitionConnections` 调用生产 `CloudConnectionVerifier.verify`；三服务实际完成且 receipt 匹配才自动启用。6.3 秒内置样本，清空用户话题，90 秒联网阶段、6 次 GPT 请求与每次 4096 输出 Token 上限 | 费用保证、自动完成账户开通或保证服务商未来兼容 |
| 历史原音不因填 key 自动上传 | schema 5 录音级 scope 包含全部启用目的地和 opaque credential generation；历史无回填；自动恢复不授予权限。点击重识别绑定当时已应用配置，变化后只走本地 | 泛化服务 consent 可以追溯授权以前的私人档案 |
| 无 key 本地启动和识别 | 未验证云配置在 AppModel 初始化时降为本地；打包 App 隔离启动/重启及 300.03 秒待命已验证。实际已安装 Apple 框架对 8 条合成中文产生候选、统一文字及可派发内容 | 8/8 完成就是 8/8 转写正确；CER 实测为 0–0.263，未做真人讲话质量验收 |
| 原音、文字稿、删除及恢复 | Store/PCMJournal、实际 SIGKILL、故障写入、原音删除保留所有文字、用户编辑/草稿优先、搜索、重识别和升级内容比较。独立进程检查 12 项、10 万记录/30 万版本规模结果 | 所有磁盘/硬件故障均已实际发生验证 |
| 实际原生外部输入 | 普通 AX 9 项、owned-range AX 9 场景、headless DOM 20 项、WKWebView 上下文 6/6，均绑定当前代码；无重复、无自动发送、有明确不确定投递 | 所有浏览器/前台目标发现均已通过；参见下列限制 |
| 打包、安装、升级及回退 | `install-upgrade.json` 8 项和 `uninstall-reinstall.json` 2 项；同包实际启动、保留合成原音/稿件/投递状态、三次重启、强退、旧版拒绝 schema 5、完整目录副本回退 | 已替换 RC1、已访问真实数据库、已完成 Developer ID 公证 |
| 长期稳定性和资源 | 最终包 5 分钟待命、VAD 内存回归及 Store 规模通过；生产 ring/converter/VAD/journal/Store 合成运行实际 1800.40 秒，输入队列 drop=0，事后 18 项核对通过 | 24 小时连续运行、整机能耗或长时间云 ASR/GPT 测量 |

## 关键入口的只读核对

1. `RecognitionConfiguration` 默认双音频专家与一个 GPT 核心，其他专家关闭；生产检查只接收必要三服务。GPT 是候选文字融合，不伪称听取原音。
2. `CloudConnectionVerifier` 在任何 provider 会话前检查授权和三服务配置，只使用校验过的内置样本及独立临时 Store；生产 `onReady` 来自实际协议认可，而非 socket upgrade。未满足完整流水线时 `canEnableCloud` 为 false。
3. `CaptureWorker.beginUtterance` 在第一个 await 之前冻结配置；`retry` 检查录音 scope，并保留 factory generation。自动本地回退遇资源不可用会释放 claim，不耗尽三次恢复次数。原音持久化不等待云端。
4. `Store.selectAutomaticRevision` 保护用户修改稿和编辑草稿；派发范围及修正所有权独立记录。整段删除与只删除原音仍是不同事务语义。
5. `AXInputAccess` 生产入口确有实际前台/焦点解析；普通插入和所拥有范围修正的安全路径使用被验证的目标、UTF-16 范围与 Store reservation。当前本机测试有意仅替换目标选择边界，不能据此宣称生产前台解析已验证。
6. Keychain 查询禁止交互式身份提示；元数据存在检查和真正读取区分。设置变更/密钥操作先撤销云代际；同步凭据读取返回后再次检查代际，退出等待所属任务结束。

## 必须随交付保留的限制

- 真实云 API、账户/地域权限、真实准确率、双专家+GPT 对最强单模型的收益和确认延迟仍未验证；不要使用任何 LIVE/QUALITY/PRODUCTION 完成状态。
- 真实麦克风/环境讲话未采集；目标候选的系统麦克风和辅助功能授权仍须由用户按 macOS 正常流程完成。当前不邀请用户充当测试员或覆盖 RC1。
- 实际 Apple 验证只有已安装资源和合成中文；不宣称任意语言、任意设备的离线能力，也不把 CER 的非零错误隐藏在完成计数中。
- 当前原生 AX 使用隔离的已知 PID 选择边界；生产前台目标解析为 **NOT_RUN**。历史合并 AX 安全条件失败仍为 **UNKNOWN**，后续通过不能解释缺失的原始计数。不存在据此声称“所有历史输入安全信号已根治”的依据。
- WKWebView 后台 setter 返回认可却未改变 DOM 值，已标记一次 unverified 且不重放；只确认上下文拒绝和不自动发送，不能宣称浏览器文字插入成功。
- 包为 arm64/macOS 26+、ad-hoc 签名，未做 Developer ID 公证；正常 Gatekeeper/TCC 流程不能绕过。升级是 schema 5，旧版回退必须使用完整升级前副本。
- 待命资源是进程范围、空隔离库、无麦克风/ASR；30 分钟合成录音也不等同于整机功耗或长时间真实云端资源表现。

## 最终完成与交付收尾

1. **已完成：**1800 秒运行正常结束，实际墙钟、帧数、队列丢帧、持久化覆盖、资源摘要及最终 source-after 已对齐冻结 SHA，见下列独立终态复核。
2. 将最终包、测试 receipt、当前状态、限制和交付索引提交到 PR #6；把 `3f49682`、旧 55 项等记录明确保留为历史/中间结果，不混作当前最终结果。
3. 最终状态分开写：`NO_API_ENGINEERING_READY` 与 `LIVE_CONNECTION_PENDING`，交付报告链接根代理统一提交的完整证据。模拟器报告中的 readiness 值只是注入证据标签，不是整个产品自动取得交付资格的判据。

除此以外，本次有界审计没有提出新增模型、重复架构、重新排名或要求用户提供临时日志的工作。新的真实服务兼容问题应在未来一次性授权的内置连接检查中准确呈现并修复，不提前伪造成功。

## 30 分钟终态的独立复核

原审计完成时该任务尚在运行。现已读取最终 `local/realtime-assessment.json`、原始 `realtime-run.log`、`source-after.json` 及更新后的 `local/README.md`，将上述待完成项关闭：

- 进程正常退出，原始计时为 **1800.40 秒**；生产 39,690,000 个输入帧，输入队列 `dropped_frames=0`。
- 生成 **60 条记录、179 个关闭的 WAV**，保存 **28,798,514 个 16 kHz 帧，即 1799.907125 秒**。记录全部关闭且原音可用。VAD/转换后的保存时长与输入时长不同，不能把队列零丢帧扩大为全部输入逐样本原样保留。
- 事后 18 项检查全部为 true：每个 WAV 的头、载荷和 Journal/SQLite 帧数一致，记录合计与 chunk 一致，SQLite integrity 通过，schema 为 5，隐式云授权记录为 **0**。
- `local/source-before.json` 与 `source-after.json` 的 **200 个来源文件哈希完全相同**；HEAD 仍为 `d4b9dbe812b9084f1bf31c1817c7b67095e17fc7`。探针二进制和合成 AIFF 输入保持一致。
- 40 次进程采样的 RSS 为 **15,664–17,936 KiB**；原始 `/usr/bin/time` 最大 RSS 为 **19,005,440 bytes**。用户/系统 CPU 共 **27.36 秒**，除以墙钟约为单核 **1.52%**。这些是此隔离进程的观察，不是整机能耗或长时间 ASR/GPT 资源结论。
- ASR 在 soak 中有意关闭，因此 `pending_asr=60` 属于测试配置，不是宣称这些记录已识别；实际 Apple ASR 的八条合成语料证据独立记录。

最终 assessment 文件 SHA-256：`d9fa25edff736b5eb7a0657de0b8589ba5ad77c0007dea67b1dff41639a79a3c`。本复核未重跑采集或更改任何 Sources/tests/scripts。此前的真实云端未验证、历史 AX UNKNOWN、前台 resolver NOT_RUN、WKWebView unverified、系统授权及未公证限制继续有效。
