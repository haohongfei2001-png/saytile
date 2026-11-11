## V1 夜间体验候选

夜间候选继承麦克风修复，统一使用正式身份并保留既有个人资料隔离。固定输入设备的 UID 已与瞬态 CoreAudio ID 解耦。Qwen 对齐两次真实候选后可在句中恢复增长；损坏权重和残下载可从设置中清理。插入范围与暂停状态已收口，安装镜像内沿用个人体验文件名。 [本轮记录](V1-NIGHTLY-EXPERIENCE.md)

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
