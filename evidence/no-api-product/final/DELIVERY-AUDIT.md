# 有界交付审计 — no-api.3 / ef2f8f8

**最终结论：冻结运行时 ef2f8f8 / no-api.3 的本轮无 API 工程基线与分层验收已经闭合；在这一明确范围内，证据支持 `NO_API_ENGINEERING_READY`，同时保持 `LIVE_CONNECTION_PENDING`。** 新 30 分钟完整保存波形与独立参考逐字节相等；交付副本已核对。本次有界复审未发现新增确证 P0/P1。此结论严格保留下文硬件/前台环境等未实测边界，不代表 LIVE、QUALITY 或 PRODUCTION 就绪。 **随后并行确认的紧凑文字面板目标尚未实装，不在这个包内；不能据上述状态宣称最新 V1 视觉目标已经完成。**

本审计依据最新用户《无 API 条件下完成完整产品开发：最终凭据接入即可启用》要求，核对冻结源码、实际执行日志、包和原生界面。运行时为 `ef2f8f84f377197350e6384f79af12a9b56272fd`，tree `126d4e2b2c24ea82f016708c03f9567cb297afab`。未修改 Sources/tests/scripts、访问私人资料、读取实际凭据或调用真实服务。

**no-api.2 的旧 READY 建议已被中段漏音事实推翻，不能用于此次交付。** 历史正文保留用于溯源；当前应读 `../intermediate-d4b9dbe/SUPERSEDED.md` 和 `../audio-buffer-ownership/README.md`。队列 drop=0、WAV/数据库一致或正常结束均不足以单独证明采集完整。

## 已核实的来源与安装包

- 本地完整原生/localhost 套件 **379 个测试方法 / 46 个套件 / 499 个展开场景**，未跳过；其中生产网络客户端实际执行 **50 个 localhost case**，协议违约为零。不同层级计数不相加为“产品通过率”。见 `protocol/README.md`、`native-network.log`、`wire-audit.json`。
- 两项 CI 已终态 success；`protocol/ci-snapshot.json` 与日志 SHA-256 复核相符。Native 实际为 Swift **6.3.3**，379 tests / 46 suites、66 AppModel；checkout 是 merge `760f8741193e2a6c60e42629560eb9fa7c5aa0fc`，其 tree 与 ef2f8f8 相同而 commit 不同。CI UI 只渲染 **16 图、controls NOT_RUN**；本机 22 图/34 press 的实际操作证据单独记录。
- 本次 AppModel **66**、headless DOM **20**、普通原生 AX **9** 已实际执行通过；WKWebView 观察 **6/6**、两项能力拒绝、零发送。`input/receipt.json` 记录全部执行前后源码和二进制哈希；198 个来源文件无变化。与 protocol（204 文件）、local（201 文件）、package（200 文件）清单共有的 198 项全部一致，额外计数来自各自包装/契约范围。
- 实物 App 二进制 SHA-256 为 `a0bf7450a4b2a97db3bbeed916066544787b0e68d9bcaa15f57f61174e72f559`，DMG 为 `d3a3fbeef54d6a89a36364a36aed7f89bed07762a34386ce5e5356db233cbd33`。审计重新读取实物计算，两者匹配 `package-identity.json`。Info.plist 指向上述源码、未脏构建、版本 `1.0.0-rc.2-no-api.3`、菜单栏应用及最低 macOS 26；二进制 arm64。
- `install-upgrade.json` **8 项**、`uninstall-reinstall.json` **2 项**通过，均绑定同一二进制：实际已发布 RC1 的临时副本、候选升级、三次重启、强退恢复、重复实例拒绝、整库备份回退、仅卸载临时 App 后重装保留原音/文字。没有操作已安装 RC1 或用户库。
- `ui/manifest.json` **22 图、34 AXPress、6 AXSetValue、6 次原生字段提交（含 3 SecureField）、9 组交互**，同一包且无脏源；22 张图片逐一重新计算哈希并相符。实际查看费用授权、连接成功和紧凑档案图片：费用范围、旧音频保护、原音已删除与用户草稿保留状态均可见；不以截图代替脚本中的真实控件操作。
- `app-idle.json` 与原始 `app-idle.log` 绑定同一包：**300.023 秒**，暖态 RSS **59,248–80,288 KiB**，结束 **59,248 KiB**；user **1.74** + sys **0.35** 秒，约单核 **0.70%**。脚本按计划 SIGTERM 结束，所以 time 的“terminated abnormally”不是未披露的崩溃。只测独立空库、无麦克风/ASR/窗口/全局快捷键的进程待命。`startup-focus.log` 单独通过，exit=0、前台不变。

## 用户要求与实际覆盖

| 要求 | 当前证据及关键入口 | 严格边界 |
| --- | --- | --- |
| 真实协议、完整 PCM、错误与退出 | 正式 URLSession WS/HTTP 适配器对 stateful localhost 服务；双专家收到相同 PCM 与短尾、partial/final、错误分类、取消、重复/迟到、GPT 持久 Responses 会话和同模型 HTTP 回退 | 模拟服务不是实际供应商；不证明现网账户权限和模型可用性 |
| 单一文字流与 EOS | 完整套件执行生产 session→engine→Store，三次可见修订、证据不支持的结果不可派发、迟到和用户编辑保护；结束产生完成或明确失败 | 不等于真实讲话质量、融合增益或云端延迟 |
| 首次三个服务的消费者流程 | 实际填写三 SecureField、Qwen Workspace，保存/三个 consent/费用授权/start；成功自动启用、失败与取消卡片均由真实 AppModel 控制路径验证 | **成功截图与 receipt 为 TEST_ONLY 注入，绝不是 LIVE 云端成功。** 向导 fixture 不读 Keychain；其他设置渲染仅随机隔离 namespace 元数据查询，不读取密钥 |
| 保存 key 后受控自检 | `checkRecognitionConnections`→生产 `CloudConnectionVerifier.verify`；只在 receipt 完整且配置匹配时启用；内置 6.272 秒样本、清空用户话题、联网阶段 90 秒、共享 6 次 GPT 请求及每次 4096 输出 Token 上限 | 不保证账单金额，不自动开通服务，不上传档案或麦克风 |
| 授权、账户变更和旧音频 | schema 5 每录音全部启用 scope；含目的服务/模型/地域/Workspace/purpose/opaque credential generation；旧历史不回填；自动恢复不授予权限；手动重识别绑定点击时已应用配置；读 key 前后代际校验和退出 drain | 不将保存新 key 解释为旧私人音频上传许可 |
| 无 key 本机运行 | 未验证云配置启动时降到本地；实际 Apple 已安装资源对 **8/8 合成中文**产生候选、统一证据、非空可派发文字 | CER **0–0.263**，保留术语/漏字错误；不称 8/8 完成即准确，不证明其他语言、设备或真人环境 |
| 原音、用户稿、历史及恢复 | Store/PCMJournal 故障和 SIGKILL；12 项进程/迁移测试；只删原音保留文字和修改稿；搜索/编辑/重识别；10 万记录、30 万版本真实 Store 查询 | 磁盘/硬件所有故障不是全部实机制造；详细规模和资源边界见 local/README.md |
| 外部输入 | 普通 AX9、owned-range AX9、DOM20、WK context6/6；真实隔离 NSTextView setter、UTF-16 增减和后续追加、用户手改/焦点/关闭/不确定投递保护 | 已知 PID 选择 seam 不等于生产前台 resolver；WK 未写入成功；历史合并安全信号仍 UNKNOWN |
| 音频输入归属根治 | production run 使用同一 `convertCapturedSamples`；每 batch 直到 callback 真正接收才退役；未接收且无输出即失败，不补静音/调 prime。四采样率逐字节回归，以及本次 1800.42 秒 / 28,800,000 帧完整保存波形对照均通过 | 只证明此次冻结源码与合成输入完整，不替代真实硬件采集或任意输入的普遍证明 |
| 打包、权限和升级 | 同一 arm64 包实际安装/启动/升级/卸载重装，独立系统 Keychain namespace 测试、无权限/请求守卫、schema 5 拒绝旧版写入和完整副本回退 | ad-hoc 未公证；用户 TCC/Gatekeeper 正常授权及真正多设备/锁屏环境仍有限制，未绕过 |

## 最终终态复核

1. **长流完整性已完成。** 原始 `local/realtime-run.log` 记录 **1800.42 秒**、39,690,000 个 22,050 Hz 输入帧、queue dropped=0、60 条完成且可用的记录；没有采集错误，进程正常退出。`realtime-assessment.json` 的 **22 项检查全 true**，179 个 WAV 实际 payload 合计 **28,800,000 个 16 kHz 帧，恰好 1800 秒**。原始十进制 `1799.9999999999977` 是逐条浮点时长求和，不能与此前真实 1486 帧缺口混同。
2. 审计读取实际 assessor：按 recording 创建时间和 chunk ordinal 逐个读取 WAV 全部 payload，与独立 reference 对应字节比较，还要求 reference 完全消费、总帧数相等。最终 **different_sample_frames=0、first_different_sample_frame=null**；保存 PCM 与 reference SHA-256 均为 `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`。这已覆盖开始、中间和结尾，没有仅凭时长、内部文件一致性或 drop=0 得出完整结论。
3. 每个 WAV 的头/实际载荷与 Journal/SQLite 相符，schema 5 integrity 通过、隐式云授权 **0**。`local/source-before.json` 与 `source-after.json` 的 **201 个来源文件**全部相同，HEAD 仍是 ef2f8f8；探针及合成输入身份不变。60 条 pending ASR 是此次刻意关闭识别的配置，不宣称已转写。
4. 长流 CPU **16.02 user + 11.83 sys 秒**，约单核 **1.547%**；40 次 RSS 采样 **14,432–17,760 KiB**。`time` 最大 RSS **18,579,456 bytes**；这是合成 debug-kit 采集进程，不能混作打包 Release App 的整机能耗。已读取更新后的 `local/README.md`，数值和范围一致。
5. **交付副本已落盘。** `delivery-paths.json` 指向正式项目 `dist/rc2-no-api.3/Saytile.app` 与 DMG。审计重新读取交付副本二进制及 DMG 并计算哈希，均与已验证包相同；Info.plist 源码/无脏标记相符。receipt 记录严格签名通过、RC1 二进制前后相等、main 未改、未替换 RC1、未访问生产资料。交付副本没有额外启动，不冒称重复完成一次安装验证；安装验证来自同字节包的独立临时位置。
6. **文档一致。** `docs/V1-NO-API-DELIVERY.md`、README 和三项 V1 状态文件使用上述两种状态；历史检查点醒目标注为历史，没有拿旧源码结果代替本次证据。仍须由根代理把这些最终证据/文档统一提交 PR #6，运行时不再变化。

最终 assessment SHA-256：`d2f9d6167798b5baeb4446e2ffecad242569f588948a2fca58cafb9d2d49b188`。本次终态复核只读日志、清单、评估代码和交付文件，没有重跑测试或更改运行时。

## 交付必须保留的限制

真实云 API、账户/模型权限、真实讲话、融合对最强单模型的准确率收益及确认延迟均未验证。不得授予 `LIVE_PROTOCOL_VERIFIED`、`LIVE_TRANSCRIPTION_VERIFIED`、`QUALITY_VERIFIED` 或 `PRODUCTION_READY`。

已知原生 AX 运行只测试隔离目标选择；生产前台解析为 **NOT_RUN**。历史合并 forbidden-operation 条件失败仍 **UNKNOWN**，原始逐项计数缺失，后续通过不能重新解释。WK 后台 setter 认可却不改 DOM，按 unverified 一次且不重放；不宣称浏览器输入成功或任意外部应用兼容。

真实麦克风/环境对话未采集，Apple 验证为已安装中文资源和合成语料。系统授权需要按 macOS 正常流程完成，不让用户承担工程测试。包为 arm64/macOS 26+、ad-hoc，尚未 Developer ID 公证。schema 5 回退须使用停机后的完整升级前目录副本。待命和合成录音资源是隔离进程范围，不是整机功耗、长时间真实云识别或 24/72 小时稳定性认证。

在上述明确边界内，本次有界审查没有发现仍需新增核心功能才能接入真实凭据的确定遗漏；不新增模型、排名研究或要求用户临时调试。真实凭据可用后，剩余工作是现网连接/转写/质量验证和据实发现的兼容修复，不能预先宣称这些已完成。

## 短证据补充复核

新增的 `UI-REVIEW.md` 和 `docs/V1-NO-API-DELIVERY.md` 与上述实际结果一致：未把短测、CI、向导成功截图或 reference 单独完成冒充最终长流成功。报告明确披露物理热拔/睡眠/锁屏/撤权、多显示器、真实环境讲话、24/72 小时与整机能耗的未实测边界；没有提出由用户做临时排障。未发现需要修改运行时代码的确定问题。该次补充复核先关闭待命、启动焦点与 CI 的待核对项，当时保留长流待定；现在由上方最终终态复核关闭 30 分钟保存波形和交付副本项，保留全部既有证据边界。

## 发布时并行设计目标的边界

远端新增 [设计提交 5d55d74d228ecb5597a4b95c9953c22389f2546c](https://github.com/haohongfei2001-png/saytile/commit/5d55d74d228ecb5597a4b95c9953c22389f2546c)；本审计通过 GitHub connector 读取其完整文档和 commit diff。它新增 [`SAYTILE-V1-COMPACT-TRANSCRIPT-PANEL-DESIGN.md`](https://github.com/haohongfei2001-png/saytile/blob/5d55d74d228ecb5597a4b95c9953c22389f2546c/docs/SAYTILE-V1-COMPACT-TRANSCRIPT-PANEL-DESIGN.md)，明确为用户确认的 **目标设计**，不是已实现声明，且要求实施前核对 PR #6 最新 head。

这是具体的后续 V1 界面实现工作，不是已经通过的无 API 测试，也不能隐去为主观审美差异：

- 新目标为 320–360 pt 宽、常态约 200–260 pt 高、最大高度约 480 pt；当前包仍创建 400×550 pt panel，输入视图 minHeight=420。
- 新目标要求 transcript 在主内容首行、低频动作收入更多菜单；当前包仍有“此刻”标题、永久模式切换、日期/状态和底部复制/插入等常驻控件。
- 新目标要求单一整合开始/暂停/恢复控制、至少 34 pt 命中区域，以及无声收音仍标“聆听中”；当前包尚未按这份目标重新布局和验收。

保留设计提交为后续交付祖先能避免覆盖并行工作。no-api.3 的运行时、包身份和测试仍对应 ef2f8f8；文档加入历史不等于旧包自动实现新设计。**当前 22 图/34 控件操作只证明原有原生界面的实际行为，不构成新紧凑面板的视觉或交互验收。**

本次没有临时修改冻结 Swift UI、重建音频状态机或重跑测试。新设计应复用现有引擎，在明确的后续界面实现中完成尺寸、状态、单按钮热区、滚动/选择及定位回归后再形成新包。因此最终报告应同时写清“云接入核心已完成”和“紧凑文字面板目标尚待实现”，不能泛称最新目标下完全只剩填 Key，或宣称 Saytile V1 的最终视觉已经完成。
