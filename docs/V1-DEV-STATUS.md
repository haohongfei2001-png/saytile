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
