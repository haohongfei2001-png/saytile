## 2026-11-14 · 0.15 自然段整合

主板与档案共同以15秒实际讲话间隔形成自然段；默认60秒形成时间组。完成有界分页、按整段回听/收藏、直接编辑、显式删段界及撤销、冲突草稿保留。独立审查的4项问题已修。已安装0.14（478）尚未替换。下一步最终SHA的完整CI、签名、升级回退和同一路径原位更新。 详见[NATURAL-PARAGRAPHS](NATURAL-PARAGRAPHS.md)。

## 2026-11-14 · 0.14 窗口共存候选（原生收口，待签名包与 CI）

基于已安装 0.13（476）产品源码 `0fbca1d892bbc8aa550c4439b8cfcb045af825ae`，独立分支 `codex/panel-window-boundary`。新增设置中的浮板/实体边界，默认浮板；AX 只读窗口几何/控件角色，不读取文档、标题或输入内容。边界调整只作用于普通可移动窗口；全屏窗口不改，改用更遮挡的原毛玻璃及有限平移避让。未改识别、SQLite、录音、已有资料或其他项目。

- PASS：原生 Swift 编译；167 项 AppModel 检查及真实 VoicePanel 鼠标事件/持久化回归；14 组几何测试函数的 881 条纯 Swift 断言（完整 Swift Testing 待 CI）。28 项真实隔离 AX/原生窗口检查 PASS，含控制器实际移开全屏按钮并恢复；4 项材质组合 PASS。详见 evidence/panel-boundary/。
- NOT_RUN：新包安装、最终 CI；签名安装与交付收据将在同源独立证据分支补齐，本阶段不冒称正式发行。
- 麦克风保持 NOT_RUN（用户要求合盖不测）；不运行云端或收费调用。
- 当前安装476保持原状。下一步：最终 SHA 的完整 CI、签名候选、合成资料升级回退和一次原位更新。

## 0.13 · 中文预览稳定性（466）

0.13（466）修正了临时句号闪动及长句里两处改词导致后续已确认文字停发的问题，保留同一 Qwen 0.6B 与最终解码。已在原来的中文识别候选路径安装并启动，签名镜像内源码为 `ff8f8a014bd6b554a5703971a1139d94da155a6c`。 [本轮机器验收](../evidence/mandarin-preview-20261114/DELIVERY.md)

## 0.13 · 连续讲话更新（442）

0.13（442）保留 Qwen 0.6B、最终解码和既有原音。改用约 0.5 秒的增量步长，保留第一次 0.8 秒上下文。修正中英混说时英文大小写、连字符或中文逗号导致已有前缀误判，从而阻止后续词上屏的问题。代码 `d3b37a88`。签名候选已原子更新到原路径并启动，正式 App 373 和 414 回退包保留。 [同一设备对照与证据](../evidence/mandarin-cadence-20261114/README.md)

## 内测 0.13 中文识别独立候选

从 PR #23 的内测 0.12 建立 PR #27。候选单独存放档案、模型和设置。实际识别引擎写入每段记录；模型加载失败后保留原音，下一段使用已就绪的本地引擎。M5 上 Qwen 0.6B 去掉强制中文提示后，同一 420 段归档为 910/10,663 错（8.53%），对照已安装版 Apple 为 1,261 错（11.83%）。原速 15 段全部在结束前多次出字。最终签名包为 0.13（414），产品源码 `cd41c60f0d7cb042c066c42147a58085b6f33f95`。38.8 秒连续讲话用同一份 PCM 重放，定稿从 10.24 秒降至 0.29 秒，两个归档段逐字一致。15 段原速验收已完成。连续输入 905 秒与完整直通对照均已完成，签名候选已在本机启动。个人口音和 8 GiB Mac 尚待验证。[机器验收与交付决定](../evidence/mandarin-quality-20261114/delivery/release-decision.json)

## 当前：Saytile 内测 0.12

菜单栏使用固定的 tile 字形。面板可见时菜单提供「收起语音板」，隐藏时提供「展开语音板」。窄板快捷菜单提供「恢复阅读尺寸」。

## 内测 0.11

档案使用录音时已保存的时间组，文字、收藏和原音仍指向各自的原记录。短停顿不生成新标题；点击正文直接编辑。修复首次 PCM 检查点失败及换块空尾损坏后的恢复。详情草稿与浮板改同一段时须核对较新的文字；两份内容均保留。旧的无基准草稿能继续打开。

已安装签名 build 369，源码 `3b10cc5`，详见[档案与中断恢复验收](../evidence/internal-0.11/README.md)。

## 内测 0.10

0.9 在窗宽达到 80 pt 时强制改变高度，展开时再取回先前高度。本轮将窗口的两条轴独立处理，让窄板上的收音键与普通窗口使用同一组布局和命中坐标。

本机已在原位置运行签名的内测 0.10 build 367，程序源码 `b2f2f4ce673ebf32be3adf672ea9593a73ed8484`。[原生演示与验收记录](../evidence/internal-0.10/README.md)。

## 内测 0.9

只调整缩到最小时的外观、点击与恢复。旧版的中央胶囊占 54 × 26 pt，位于 72 × 44 pt 的窗口内；单击四周可能被按拖动处理。现在小板自成一块，收音、拖动与恢复各有明确行为。

已在原位置更新并启动内测 0.9 build 364，签名产品源码 `b1ad55085f31a9a16bd9216c3c42ff2e01d06c26`。[本轮实机验证](../evidence/internal-0.9/README.md)。

## 内测 0.8

继续使用唯一的 Saytile.app。批量清理保护没有有效转写的原音；新一组尚未出字时复制最近已有文字的时间组；撤销至原文释放多余草稿；浏览器绑定减少 AX 往返但完整保留写入前的所有权检查。界面没有重新设计。

现已原位安装并启动内测 0.8 build 360，签名程序源码 `f18c2b5f2ad15aec7f66cc34fa79ad671936a532`。[安装记录](../evidence/internal-0.8/installation.json) · [本机与独立原生验证](../evidence/internal-0.8/README.md)。

## 内测 0.7

首页统一语音档案、行内收藏和设置导航；首次打开进入档案，同一窗口支持切页和编辑。 本机已原位更新并启动 build 356，产品源码 `c34edb428a80d36857304972cb69e98319573aae`。[本轮机器收据](../evidence/internal-0.7/acceptance.json)。验收只使用合成档案；Chrome 直接输入的切换目标场景仍未通过。

## 内测 0.6

本机已原位更新并启动 build 353，产品源码 `e9fc066`。见[本版原生窗口及安装收据](V1-TEST-RESULTS.md)。

语音板只显示连续可编辑的文字、复制键和语音键；仅语音键控制收音。菜单控制浮窗显隐；设备及故障在设置中查看。本地模型直接选用，云账户配置与启用在线处理相互独立。安装资料位置、应用身份与识别引擎未变。

## 内测 0.5

已安装并运行 build 350，源码 `745acb2`，只替换应用包。菜单栏单击展开菜单，浮窗显隐独立于采集。首次默认显示；明确收起或显示后，重启保留该选择。缩放只改变可读面积，最小状态只展示同一个语音按钮；[验证记录](V1-TEST-RESULTS.md)。

## 内测 0.4

既有 0.3 处理自动跟尾，0.4 已原位安装，修复用户上下翻阅时整行重新折排、滚轮跨页余量和历史空录音导致的翻页空白。详见[实际窗口对照](../evidence/internal-0.4/reader-motion.md)。说话时首批立即显示，仅活动识别稿的真实追加按短帧显示；手选、键入、复制、回读位置及用户手动换行均保留。参考 [Gboard 高级语音输入](https://support.google.com/gboard/answer/11197787?hl=en) 的听写时可手动编辑，以及 [Amazon Transcribe 的增量文字说明](https://docs.aws.amazon.com/transcribe/latest/dg/streaming-partial-results.html) 对稳定部分与可修订部分的区分；未接入其服务，亦未对其帧率或中文准确率作比较。

语音板按一份连续正文显示。空闲、跨日或新讲话不插入空行；普通换行取决于窗宽和用户编辑。

唯一产品入口为 Saytile.app，每次对用户交付小功能更新，将内测编号依次递增（0.0、0.1、0.2、0.3、0.4）。同一轮的中间提交沿用本轮编号。拖动和缩放时将整个窗口约束在所在显示器的可用区域；指针进入另一屏时可将整个浮窗移至该屏。「显示边框」独立于窗口位置、尺寸和资料。单击正文即可手写或修订语音；保留原始录音的段落身份。四边采用等距光学留白，语音板完全移除滚动条，触控板、滚轮和键盘均可翻阅历史。用同一份共享编辑器接入 Nearpane，两个应用的资料仍隔离。

## V1 原生产品界面

已从 PR #18 建立独立原生界面分支，记录 build 269 的审核结果与实现范围。 [设计记录](V1-NATIVE-PRODUCT-DESIGN.md)

## PR #18 前台输入

前台测试改为一次激活。真实 AX 与独立 DOM 检查首次、追加、人工操作及取消，生产输入源码和个人体验版沿用 build 269。 [验收记录](V1-FOREGROUND-RELIABILITY.md)

## V1 夜间体验候选

夜间候选继承麦克风修复，统一使用正式身份并保留既有个人资料隔离。固定输入设备的 UID 已与瞬态 CoreAudio ID 解耦。Qwen 对齐两次真实候选后可在句中恢复增长；损坏权重和残下载可从设置中清理。插入范围与暂停状态已收口，安装镜像内沿用个人体验文件名。为 Xcode 26.6 显式传入登录项回调，并补齐设备选择器的原生辅助标签。 [本轮记录](V1-NIGHTLY-EXPERIENCE.md)

## MacBook 内置麦克风 · 个人体验修复

已在安装后的签名体验版复测设备拒收和公开音频实时窗口；空闲复制检查改为等待实际动画终点。

内置麦克风合盖断开不再显示待命；不切换输入设备。归档显示清楚的拒识原因，保留原始诊断。 见[验收范围](V1-BUILTIN-MIC.md)。

## V1 统一发行候选

整合版本 1.0.0-rc.2-integrated.1 已生成 Developer ID 签名 DMG，正式产品源码 235b2944。 [本次完整交付](V1-INTEGRATED-CANDIDATE.md)

## M5 本地中文实时识别候选 .6

工程候选为 `1.0.0-rc.2-local-asr.6`，产品源码 `a55d51a1ff4711340bc63ea5c8ecd927dd2327d3`。安装包 61,646,743 字节。M5 原生实测支持 Apple 默认、Paraformer 轻量备选及 Qwen 手动选择。Zipformer 仅进入研究。发布等待 Apple 公证，研究权重的商用许可尚未确认。 [评测与交付报告](V1-MANDARIN-LOCAL-ASR.md)

## RC2 连续时间轴整合候选

独立分支继承 PR #12，恢复正式应用、偏好、档案与 Keychain 身份。已修复编辑期间空白面板复制旧组、午夜归日取整两项实测缺陷。发布继续等待真实云端和公证。[独立终审](V1-RC2-TIMELINE-INTEGRATION.md)

# 连续时间轴独立预览

独立 Draft PR #12 已实现跨日期分页、空闲留白、原文就地修订与选区复制。签名预览使用独立资料目录。 [完整交付及验收](V1-CONTINUOUS-TIMELINE.md)

# no-api.10 开发状态

冻结产品源码为 `5639058e6b178027861b18cc0521387487c919d5`。PR #10 的后续提交保存安装包、实验驱动和收据。生产 main、RC1 和 no-api.9.1 独立保留。

- 录音开始时固定一个已核验的 ASR，GPT-6 仅处理候选文字。Auto 缺少讲话语言证据时使用本机识别。改动模型、授权或凭据会使原有连接回执失效。
- WKWebView 的原生写入可在实际成功后返回超时。派发器只执行一次写入，再读取并比对受限范围及前后文字。所有权、窗口、焦点或内容发生变化即停止修改，未确认投递在重启后不会自动重放。
- 修正原生设置诊断替身对未选模型的凭据要求。实际安全字段、菜单、成功、失败和取消路径已在签名 App 上核验。真实云端保持 NOT_RUN。

[最终交付](V1-NO-API-DELIVERY.md) · [业务源码](../Sources) · [逐项机器收据](../evidence/no-api10/final/)


2026-11-10 · Saytile Cloud: Independent cloud candidate: gateway and transactions implemented; native integration follows.

2026-11-10 · Saytile Cloud: Native source selector, Keychain account, per-utterance frozen transport, hosted review and local-only history recovery implemented. Vercel project deployed; Supabase remote still not provisioned.

2026-11-10 · Commercial candidate: active-subscription recheck on delayed invoices, per-account rolling cost cap, two concurrent GPT requests and a local logout fence. Dedicated signed candidate to follow.

2026-11-10 · Fixed a real Supabase PostgREST safe-update rejection affecting paid audio admission and a missing accessibility identifier on hosted upload consent. Private candidate .2 supersedes .1.

2026-11-10 · Public WebSocket stream returned 404 on a named wildcard rewrite. Use literal v1 routes to preserve the query-free admission contract; local auth, quota and consent logic is unchanged.

2026-11-10 · Gateway now revalidates both the original identity and the lease every five seconds. An already open stream cannot continue using a logged-out user token.

2026-11-10 · Final independent candidate source, signed private DMG, public fail-closed gateway, original design/settings screenshot and public release blockers are collected in docs/SAYTILE-CLOUD-DELIVERY.md.

### 本机实时识别候选

独立分支继承 PR #14 的 RC2、Cloud 和 BYOK。首轮将七个本机后端接到逐段冻结的工厂，共用原音日志与既有时间轴。两个 FluidAudio 模型与 Qwen 1.7B 通过档案重识别入口运行。后台评测及签名窗口验收继续。

第二轮在原生面板复现外部识别器已有文字而 UI 无更新。已修复长读阻塞，并让签名程序从资源目录加载 MLX 着色器。完整候选测评、长时回放及 DMG 验收继续进行。

第三轮完成仅文字的可选 GPT-6 复核、授权撤销、新段冻结和离线定稿保护。Qwen 分块预览限制反复改写已读前缀。已据同机对照确定系统中文首选、轻量备用及分段实验模型。下一步在干净源码上签名打包、运行每路原生面板或历史重识别验收。

本机候选 .2 将原生主板验收绑定到真实 VAD 回调和短读修复，复用生产音频环形缓冲。代码冻结后，从签名安装包重跑面板与资料升级。

在 b8d622c 签名面板逐帧复现：Qwen 把“二十九”重写为“29”，读者保护一直拒绝后续同源候选，5.03–17.10 秒不再更新。仅允许两次连续候选对同一有限预览尾部达成一致且保留原话片段时恢复；不改外部稳定前缀、不拼接候选。候选包升至 local-asr.3。

本机识别候选 local-asr.3 的签名安装包、安装/回退凭据、原生面板及窗口录像已归档到 deliverables/local-asr 与 evidence/local-asr。保留所有冻结版本，待完整成对测量与功耗收据。

本机识别 local-asr.3 工程收口。独立 PR #15 的源码 e7c4ac8 已打包，后续提交仅补证据和测试工具。推荐 Apple 中文实时、sherpa 轻量及 Qwen 0.6B 手动分块。详见 docs/V1-LOCAL-ASR-ACCEPTANCE.md；不改 main、RC1、no-api.10 或上一整合候选。

普通话收口：继承 PR #15，Zipformer 仅开放工程评测，模型权重商用许可未获证实。独立工件与 300+ 语料测量进行中，无需用户授权、录音或付费服务。

PR #16 anchors the Mandarin comparison to application source 178dbbc073613ac3c0ea632e25b74c29ab4ef702. The independent quality fixture feeds identical pinned PCM through either a single full-wave recognition ticket or the real capture worker, VAD, journal and SQLite. Paced window observations use the installed app. The timing and accelerated paths have separate receipts.

On M5 the 0.6B cold path retained Foundation hash buffers and reached 2.35 GiB combined physical footprint. The next candidate bounds their per-read lifetime and the existing MLX allocator cache. Verification and digest rules are unchanged. The timeline acceptance now selects a visible historical line, eliminating an overlapping second programmatic scroll before testing new-utterance selection protection.

PR #16 signed local-asr.5 is bound to aa68eb5. Four 15-clip clean paced native windows, the nine-second isolated Zipformer movie, hash-verified resume, v5/v6 installation, and the 12,000-row selection regression have receipts. Final-sha 440-trial quality replay and half-hour soaks have their own directories.

A real cold download through the configured Mac proxy timed out on the previous 16 MiB request. Local-ASR .6 requests bounded two-MiB immutable ranges, isolates CDN range redirect cache keys, checkpoints a contiguous prefix and validates byte ranges and full SHA before promotion. The independent macOS transfer CI uses the public pinned files and no API credentials. ASR workers, capture, TextKit and the model assets are inherited from aa68eb5.

Design candidate: ported the production settings, archive, first-use guidance and per-display panel placement. Build 269 and its profile remain independent. Native window/AX acceptance follows.

The composed reference window exposed a shadow above the card and a neutralized center. The exterior shadow now falls below the card without obscuring its glass. Resource retry now requires an installed system asset and clears only its own previous error. Permission recovery and pre-transcript empty records retain the original two controls.

An actual initial launch with an unlaid-out menu-bar item landed in the bottom corner of the 1920 × 1080 screen. Accept a status-item anchor only at the visible display's menu bar; otherwise center the initial panel. Never rewrite saved user placement. The test rig measures actual AppKit drag displacement after its native hysteresis, then requires the observed frame to survive reopen and restart.

Real two-display dragging reproduced a shared-edge failure even though same-display dragging, menu hide/show and pure geometry passed. The unused top inset now tracks the native gesture in desktop coordinates; the app constrains the panel after release, not midway through a cross-display move. No visual chrome or new action was introduced. Work is isolated from all protected branches and profiles.

Final private design candidate: build 275, product ef21bda1807e9152f41fd8dbc2597cb30e28c9fc. Installed in parallel and left paused. See V1-NATIVE-PRODUCT-ACCEPTANCE.md for native screenshots, live panel video, source-bound tests, geometry fixes and distribution limits.
