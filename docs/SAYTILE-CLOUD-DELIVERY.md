# Saytile Cloud：独立候选交付（2026-11-10）

**当前可用：公开但不发起付费调用的网关、已签名的双模式 Mac 工程候选，以及在隔离官方 Supabase 栈完成的认证识别链。运营方托管的商业服务尚未开放。** 不要替换生产安装或对外售卖。正式项目为 [Draft PR #14](https://github.com/haohongfei2001-png/saytile/pull/14)，基于 PR #13 的 `25991e62cab818d41f2e855620114822a46b6b67`；未合并、未创建 Release。

| 对象 | 可核对的身份 |
|---|---|
| 签名 Mac 包 | `Saytile-1.0.0-rc.2-cloud.integration.2-arm64.dmg`，正式仓库本机的 gitignored dist/engineering-candidates/saytile-cloud/，Apple silicon、macOS 26；未公开发行 |
| 原生产品源码 | `a707a0e34a2161a547de9b5b44e6cea3421d4a20`，`app.saytile.mac`，包内标记 clean；后续提交未改原生产品输入 |
| DMG SHA-256 | `dcb9d9b93241653ce192eaeb57662e8f14fd6b3cc11deac9e42389bab6978ed1` |
| 在线网关 | [版本与环境](https://saytile-cloud.vercel.app/v1/health)，部署源码 `c8603c2797c21d3dad2bd50d8750412387cb568a` |
| 证据 | [机器收据](../evidence/saytile-cloud/receipt.json)、[签名包构建日志](../evidence/saytile-cloud/packaging.log)、[原生设置截图](../evidence/saytile-cloud/settings-hosted.png)、[运营与接入说明](../cloud/README.md) |

| 状态 | 项目 | 实测及边界 |
|---|---|---|
| PASS | Vercel | 已有 Pro 团队内新建独立项目，未更改套餐。最终公网 HTTP 健康 200、无身份 401、数据库未配置 503；录音 WSS 的拒绝状态也分别为 401/503。运营探针收到心跳后主动以 1000 关闭。初次 180 秒时限测量收 35 次心跳，197.045 秒观察到 1006。没有把平台时限视作保证；录音网关主动上限 95 秒。真实切回先前部署、检查旧 SHA，再恢复候选 SHA；没有为回退重建。网络经既有代理，不证明大陆直连。|
| PASS | 多账户、授权与计费边界 | 官方本地 Supabase Auth、PostgREST、Postgres、Mailpit：两名合成用户用实际 OTP 验证；刷新令牌、拒绝跨用户 RPC、发放和撤销权益、退出后旧 JWT 401；失效的已开语音连接以 1008 关闭。Mac 钥匙串真实写入、重启恢复和清除均用单独测试服务。无权益账户触发零次上游调用。|
| PASS | 原生识别链（模拟模型） | 有权益用户的有效 Supabase 登录 → Mac 冻结录音服务来源 → 原音 journal → 二进制 WebSocket → **模拟** Qwen 候选 → 源证据签名 → **模拟** GPT → 原有 SingleTranscriptEngine → SQLite 定稿及可派发版本。1 次 ASR、1 次 GPT，3,200 字节。无后台重传已保存音频；BYOK 仍独立直连。|
| PASS | 预算和结算 | 隔离 PostgreSQL 18.6，用 12 个客户端竞争，放行两条录音，同一复核只获一次预留，另一用户可独立加入；还验证了 24 小时每用户费用上限、全平台封顶、撤权代际和账单未知保留预留。Stripe 签名事件走真实 SDK 校验，延迟的已取消订阅不发权益；未生成商户订单。|
| PASS | 稳定性（仅本地模拟供应商） | 两用户按墙钟连续 1,218.86 秒，115 段完成、5 次有意断线，74,000,000 字节 PCM；分段结算无遗留未结事件，但供应商金额仍未知。该长测在最后的 SQL 与会话撤销修复之前；两个修复均有针对性回归。模拟 P50/P95 只在原始收据中，不用作产品指标。|
| PASS | 原生 UI、安装、升级、回退 | 签名 App 的真实 SwiftUI/AppKit 窗口，38 张界面采集另加 3 张参考状态，43 次 AX 按压，其中两次切换托管上传授权。无真实前台草稿、录音、键盘事件或系统剪贴板写入。v5 → v6 验证编辑、原音、已有 BYOK 授权、回滚副本；另在独立 Applications 测试目录实际演练 PR #13 签名 v6 → 商业候选 → PR #13，时间轴、音频及合成钥匙串记录未变。|
| PASS | 完整 Xcode 原生回归 | 同一套原生产品源码：405 项 Swift Testing 全部通过，49 个套件，104 项 AppModel 检查通过。网关、原生网关及专属 Supabase CI 另行验证。 |
| FAIL（间歇） | 托管 macOS 前台输入作业 | 37430b2 首次 WKWebView 重新绑定时因页面不可观察而拒绝（TextEdit 通过）；仅重跑失败作业后，WKWebView 长短修订、手改/失焦/重启保护及原生夹具均通过，TextEdit 却返回 unsupported。未弱化保护、未观察到错投或自动发送；两次结果不拼成一次全绿。 |
| FAIL | Gatekeeper 公开分发 | Developer ID、hardened runtime、时间戳和签名完整性通过。Gatekeeper 返回 **Unnotarized Developer ID**。未认证/装订，不建议作为正式下载分发。|
| BLOCKED | 独立托管 Supabase | 所选组织创建第三个项目实时报价 **US$10/月**。仅授权免费，未调用创建/升级接口，也未占用、暂停或改动另外两个项目。本机官方栈和 CI 都不是托管 Supabase 项目。|
| BLOCKED | 商用开放 | 缺已获准的服务地域、相应数据处理与跨境告知、商户生产接入、公证授权。中国大陆不在托管放行地区；不会用代理测试替代服务商区域资格。|
| NOT_RUN | 真模型/商户实付 | 没有使用运营方密钥、真实录音、真实收费订单。Qwen 真候选、GPT 真修订、连续真实语音、首字/定稿 P50/P95、单位成本、识别准确度、BYOK 与托管对照均无实测结论。GPT 仅允许由候选证据支持的文字进入现有派发链。|

本轮真实修复包括：Supabase Data API 拒绝无 WHERE 的预算更新，Vercel 通配重写让 WSS 录音路由返回 404，退出后旧连接仍会接音频，以及托管上传开关缺少可识别的 AX 名称。回归从各自失败的层级发起；没有放宽输入所有权检查或关闭数据库保护。

**需要持有人处理的事项按依赖顺序集中如下：**（1）在已批准组织内提供可核价为零的独立名额。此前不填写密钥也不影响 BYOK。（2）独立数据库就绪后，在[这个 Vercel 项目的生产环境变量](https://vercel.com/haohongfei2001-8529/saytile-cloud/settings/environment-variables)一次录入运营方两把密钥及业务空间、地域，明确允许的测试音频与最高真实调用预算。密钥不发聊天，不进 Mac。（3）公开收费与分发前，由商户/发行主体完成收款与合规确认和 Apple 公证身份授权。迁移、部署、受控联调与复测由工程方完成，无需用户录音、操作终端或收集日志。
