## V1 夜间体验候选

本机完成 Qwen 全量冷下载并复现设备、文字和下载状态缺陷。最终原生与 CI 结果随候选收据保存。 [本轮记录](V1-NIGHTLY-EXPERIENCE.md)

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
