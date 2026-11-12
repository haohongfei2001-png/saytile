## 内测 0.3 · 实时正文与折行

产品源码 `d80a537f6038674e8755c47bbde0b28c90e6684c`，build 328。使用相同候选、时序、窗口与分辨率对照 0.2 / 0.3：公开中文回放最大相邻采样滚动 19.0 → 3.8 pt；多行突发压测 74.0 → 14.5 pt。复制后剪贴板不变，选区和回读位置不动，原生编辑写回后未被迟到修订覆盖。[并排原生动图及逐帧收据](../evidence/internal-0.3/viewport-replay.md)

完整签名 App 使用相同 10 段公开语音、单路本地 Apple 中文识别、独立数据目录、起音阈值及参考文本。两版 10/10 都在结束前出字。实际讲话时观测到的正文变化共 79 → 128 次；纯追加的单次显示字数 P95 从 5 降至 2。首批含参考内容的文字 P50 1.208 → 1.183 秒，P95 2.822 → 2.850 秒。归档字错率两版都是 52/250（20.8%），均有一个空转写子段；0.3 最长相邻更新间隔仍有 0.949 秒。[评分口径与逐条结果](../evidence/internal-0.3/paired-public-speech.json) · [宿主发布与原生观察的原始双时钟](../evidence/internal-0.3/public-speech-frames.jsonl)。未进行私人现场讲话或在线调用。

完整 449 项 Swift Testing 串行全过；之前并行运行时，只有一个依赖 150 ms 内主线程采样的窗口动画断言没采到中间帧。串行整套实测 7 个中间位置。默认测试入口现将此计时用例单独执行，再用同一二进制测其余用例：1 + 448 全过，原生窗口实测 9 个中间位置，全部断言保留。128 项 AppModel 检查通过。签名 App 原生窗口通过中文输入法、选区复制粘贴、删除、重开以及 12,003 条记录的分页回看（驻留 64 条，空闲位移 0 pt、跨页锚点差 1 pt）。本轮只有一块显示器连接。

## Saytile 内测 0.2 · 连续语音板

本机签名产品源码 `2a0e566f6cb1b8921b8dfaf517672e4ebaa371f1`。446 项原生测试全部通过。隔离的原生窗口验证了用户手动换行、选区复制、中文输入法、删除后重开以及后台修订保护。跨午夜时维持连续正文；12,003 条记录中的 64 条驻留，空闲时 18 帧视口位移为 0；触发相邻分页后，同一字形在窗口中的垂直位置变化 1 点。精确手势继续使用 macOS 原生滚动。

用同样 10 条公开音频比较已安装的 0.1 与最终 0.2。10/10 均在讲话结束前显示有意义文字。0.1 的空转写子段为 2/13，0.2 为 1/11。首批能与参考匹配的文字从声学起点计算，中位数从 1.245 秒到 1.208 秒，P95 从 2.846 秒到 2.822 秒。语料规模不足以证明普遍提速。归档字错率两版均为 52/250（20.8%），低音量专名和中英夹杂仍会识错。本次真人素材为公开录音，未采集现场讲话。[同音频比较及来源](../evidence/internal-0.2/continuous-speech.json)

## Saytile 内测 0.1 · 2026-11-13

- 安装包对应干净源码 `6271a65f17f5b749ff89427e6e2681a76a11b386`（build 315）；本机 Developer ID 签名。升级后确认原来的应用路径只有一个运行实例，安装前后使用相同 Bundle ID。
- 本机两块物理显示器。旧版在拖动中底部越界 22 pt；新版用真实 NSPanel 处理 AppKit 事件，9 次拖动／缩放、松手前 72 次位置检查均在某一显示器的可用区。覆盖四边、跨屏往返、满屏缩放、隐藏重开及独立进程恢复。断连覆盖几何规则，未实际拔插。
- 签名 App 的隔离原生设置切换「显示边框」：同一扇右上角 240 × 128 pt 窗口、同一编辑器、同一选区，左缘像素随开关变化；独立进程重开仍为关闭。未访问个人录音或重设个人偏好。
- 最终源码完整 Swift Testing 串行 440/440；AppModel 126/126。并行套件曾有一次旧的滚轮事件未移动；该次失败保留。线上第一次在 1024 pt 显示器用固定位置拖动时点到了可编辑正文。在独立可见窗口通过实际滚轮事件并让出主线程后，完整并行回归 440/440。小屏夹具改从实际两个按钮之间的留白拖动，128 × 69 pt 和正常尺寸均通过，四边与跨屏断言不变。两项均只改夹具，安装的产品源码未变。
- 同一 SHA 上的远端 foreground 作业中，隔离 Chrome 首次写入一次且文本正确，页面归属一度不明确而返回 unverified；AppKit、WKWebView、TextEdit 对照通过。此次边框与位置更新未修改外部输入逻辑。

## Saytile 内测 0.0

本机隔离原生窗口已验证：空白录入、中文输入法组合、含 emoji 的选区复制/剪切/粘贴、回车换行、删除正文，以及第二次启动后保留已删除状态及原文字版本。只用了合成文字、临时 SQLite 和私有剪贴板。本轮不把这些测试解释为云端识别或新麦克风质量验证。最新逐提交的自动测试见本分支检查。

## V1 原生产品界面

已在本机从 build 269 打开独立原生审查窗口，核对原图和品牌文件。 [设计记录](V1-NATIVE-PRODUCT-DESIGN.md)

## PR #18 前台输入

已对照旧运行的两份完整日志及附件，独立复现 WKWebView 写入前取消。本机 AppKit / WKWebView 通过 10 项主断言和 11 项独立边界场景；Chrome 与完整 CI 按最终 PR head 收据核对。 [验收记录](V1-FOREGROUND-RELIABILITY.md)

## V1 夜间体验候选

本机完成 Qwen 全量冷下载并复现设备、文字和下载状态缺陷。最终原生与 CI 结果随候选收据保存。设备断开后重新选择失效编号的回归通过；ChatGPT 访客入口 HTTP 403，未进入草稿。模型专项 12/12 通过，包含较早位置修订、损坏缓存、断点和错误整包。隔离 AppModel 验证通过 120/120。工作树包含全部 PR #10 至 #17 的提交。首轮完整 CLT 422/422 通过；完整 Xcode 的 Swift 6.3.3 在 Views.swift 生成 @isolated(any) 布尔回调时崩溃，改为和其他设置相同的显式闭包后重新整包验证。 [本轮记录](V1-NIGHTLY-EXPERIENCE.md)

## MacBook 内置麦克风 · 个人体验修复

两次拒收、28 次进程观察无输入；四组公开音频讲话中均出字。空闲动画末帧与复制的精确锚点断言分开验证。

在签名体验版重复两次复现内置队列收到全零仍显示待命。公开中文材料的四种受控输入均在句末前更新真实 AppKit 时间轴，非现场讲话证明。 见[验收范围](V1-BUILTIN-MIC.md)。

## V1 统一发行候选

413 项 Swift 测试、108 项 AppModel、102 段 CPU/GPU 竞争运行及真实隔离 Chrome、WKWebView、TextEdit 通过。本机代理的 Qwen 整包下载仍失败。 [本次完整交付](V1-INTEGRATED-CANDIDATE.md)

## M5 本地中文实时识别候选 .6

411 个 Swift 测试及 104 项 AppModel 检查通过。四路各完成 440 次模型直通、440 次产品回放及 15 次原速窗口测试。独立 macOS CI 通过三款模型公开冷下载。本机代理下两个整包下载超时。Qwen 在共用机器的半小时测试中取消一段，独占复测 102/102 完成。真实 8 GB 硬件与电池续航待测。 [评测与交付报告](V1-MANDARIN-LOCAL-ASR.md)

## RC2 连续时间轴整合候选

定向 Swift Testing 3 项通过，含 12,001 条既有分页回归。真实隔离窗口的空闲复制与编辑期间取组红绿复现已完成。最终签名安装演练分别记录媒体、草稿、授权及两项随机 Keychain 测试账户。[机器证据](../evidence/rc2-timeline-integration/)

# 连续时间轴独立预览

源码 86dbd24 的 405 项 Swift Testing、104 项 AppModel 检查及签名 App 的原生 AX 交互通过。逐项证据、早期失败与发行限制见报告。 [完整交付及验收](V1-CONTINUOUS-TIMELINE.md)

# no-api.10 最终机器验收

冻结源码 `5639058e6b178027861b18cc0521387487c919d5`。结果分为 25 项 PASS、1 项 FAIL、5 项 BLOCKED、3 项 NOT_RUN。这是验收场景分类；其中 Swift Testing 的独立计数为 401 通过、0 失败、0 跳过。

逐项收据保留测试环境、散列、原始输出及证据路径。补充运行曾在首次派发前安全拒绝，见前台拒绝日志。此前的签名包首次连接测试缺陷及修复过程保存在 PR 历史。

[无 API 封版报告](V1-NO-API-DELIVERY.md) · [机器 JSON](../evidence/no-api10/final/machine.json) · [完整 Xcode](../evidence/no-api10/final/tests/xcode.json) · [前台历史失败](../evidence/no-api10/final/input/prebind-refusal/receipt.json)


2026-11-10 · Saytile Cloud: 3 Node tests passed: PGlite migrations and service roles, localhost binary WebSocket/evidence round trip, Stripe signed fixture. No real service consumption.

2026-11-10 · Saytile Cloud: Local native factory → gateway fixture → SQLite final and dispatchable text passed (1 ASR, 1 GPT). PostgreSQL 18.6 concurrent admission passed. Remote Vercel probe on 7d6aaa2: HTTP 200/503/401, WS opened, 35 pings then 1006 at 197045 ms. No vendor call.

2026-11-10 · Isolated native OTP/refresh fixture plus real disposable Keychain save/restore/delete passed. Hosted UI and official local Supabase stack tested separately from paid services.

2026-11-10 · Full native audio segment authenticated by official local Supabase + PostgreSQL + isolated Mailpit, signed gateway evidence and native SQLite dispatch passed after the budget SQL fix. One simulated Qwen and one simulated GPT; denied account reached zero providers.

2026-11-10 · Signed .2 exercised the consent toggle twice with 43 native AX presses. Assertions now require all 41 preexisting presses plus precisely both named consent changes. v5 → v6 and backup rollback passed on .2.

2026-11-10 · Official isolated Supabase reproduced an open stream surviving logout before the fix; afterward the same scenario closes with 1008 and the prior JWT receives 401. The paid native fixture reached 1 mock ASR/1 mock GPT; unpaid admissions remained zero.

2026-11-10 · 405 Swift Testing and 104 AppModel checks passed on the recorded native tree. Isolated Supabase plus native stream, real Vercel routing/rollback, .2 signed migration and v6 roundtrip have machine receipts. One remote AX job produced inconsistent WKWebView/TextEdit refusals; both attempts preserved. No real vendor or merchant traffic.

本机候选第一轮在 M5 和 macOS 27.0 编译主程序及原生辅助进程。十条固定 FLEURS 中文人声已通过 sherpa、Nemotron Metal 和 Qwen 0.6B 辅助进程解码。首轮结果仅覆盖引擎出口。待从签名 App 时间轴测量实际出现时间。

同一段 16.68 秒 FLEURS 人声，修复后 AppKit 文本视图观察到 Apple 33、sherpa 26、Nemotron 48、Qwen 0.6B 14 次文字变化。七种引擎已分别完成十条同源录音。下载器实网暂停在 16,777,216 字节，恢复并校验 237,202,501 字节，重开、删除通过。104 项 AppModel 检查通过。详细机器收据随最终候选补齐。

源代码的主程序 release/debug 均能编译，七种后端的 M5 同语料输出均已入库。新增短管道回传、等长损坏权重、单路证据与离线/撤销复核回归测试，完整 Swift Testing 由本分支 CI 执行。

独立复查发现静态工具未携带资源包时会触发 SwiftPM 的致命错误。现已改为可恢复的资源查询，104 项 AppModel 检查重新通过。原生面板探针改用正式 AudioRing、重采样、VAD 和实测音量路径，收据逐帧记录讲话状态。

保留 16.68 秒授权 FLEURS 的实际失败帧 evidence/local-asr/regressions/qwen-reading-freeze-b8d622c.json。增加数字形式永久改变与无关替换的独立回归；Swift 原生构建已过，下一步从新签名 DMG 回放同一语音并重算所有四路显示质量。

e7c4ac8 · 411/411 Swift Testing，104 项 AppModel，52 个本地协议场景零违反。签名面板四种引擎各 10 段、归档三种各一段；14.94 秒窗口级录像无音轨。坏权重时保留可读 WAV；静音后释放进程；录音中更换模型只影响下一段。

e7c4ac8 实际 70 次授权真人文件推理；40 次本机 AppKit 发言中试验，3 次独立冷档案、三种正式归档路径逐行处理同一组 VAD 片段。30 分钟 102/102 记录、204 WAV、2685 次窗口更新。七路功耗有同机空闲对照。Qwen 0.6B 首字 P95 3.54 秒未达 2 秒目标；极低电平档案可为空或出现额外文字。公开分发、GPU/ANE 独立归因及付费云端状态见 evidence/local-asr/acceptance.json。

普通话收口：继承 PR #15，Zipformer 仅开放工程评测，模型权重商用许可未获证实。独立工件与 300+ 语料测量进行中，无需用户授权、录音或付费服务。

The new reference-blind manifest contains 320 unique public human clips and 20 paired acoustic perturbations. The Apple standalone test client requires its own Speech asset reservation. The independent test executable also requires its SwiftPM model resource bundle. Both fixture prerequisites were reproduced with one pinned WAV before the authoritative runs. Missing resources in exploratory runs are fixture errors.

Candidate .4 passed the local 12,000-row window run and the signed v5/v6 continuity drill. A separate CI run on the fixture-only commit failed the viewport/selection assertion after a second scripted scroll. Both prior outcomes are retained. Published .4 memory values are from simultaneous libproc physical footprints, with idle and active system telemetry separated.

Final-source Xcode CI 42833800155 passed 411 Swift tests. On the same cold waveform Qwen combined process footprint fell from 2,403 MiB to 1,442 MiB. In the signed .5 window Qwen first lexical text was 0.877/0.968 s P50/P95, with multiple reference-bearing updates in all 15 samples. The longest meaningful gap was 5.328 s. The image and the silence-only movie contain only licensed fixture transcription.

The .5 cold-start transfer through the host proxy failed on Zipformer and Qwen despite the earlier successful remote suffix repair. Native per-clip and 440-trial inference results remain valid for installed weights. The separate Qwen sole-inference soak completed all 102 recordings in 1,803 seconds. The earlier concurrent-load cancellation remains recorded.

Design candidate: initial arm64 SwiftUI build passed. Added persisted-position, isolated profile and first-transcript regressions; signed window captures and final executable are separately verified.

Interim native review on M5: 44 AX presses, 15 interaction groups, 38 ordinary renders plus three reference renders and a no-focus-change guard passed. A 45-second synthetic live stream persisted all 992,250 source frames with zero drops (ASR disabled). Real two-window composition exposed a gray cast and reversed shadow; after adjusting these, the controlled screen shows the lighter glass. Exact SHA evidence follows packaging.

Verified two active WindowServer displays on the test Mac (1920 × 1080 and 800 × 1280 logical points; both 2×). Added a regression for the observed invalid first-launch status item anchor. Physical unplug and independent 1× hardware remain separate.

On two 2× WindowServer displays, a real mouse event sequence failed on build 274 at X=8; with the fix the panel crossed X=0, landed at (-604,491) (408×298), survived a process restart at exactly that frame, and moved back. Both sides used the same foreground guard, no external text target, and a paused microphone. Release binary receipts follow.

Build 275: PASS 426 Swift, 126 AppModel, 19 compositor scenes, 44 AX presses, 12,000 timeline rows, two real displays with exact restart and a single-window on-device Apple speech movie. See evidence/native-product-design/machine.json. Protected build 269 and formal/personal file metadata unchanged; no private content opened.
