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
