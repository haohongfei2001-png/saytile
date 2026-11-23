# Saytile Cloud • 独立候选

此网关和 PR #13 的原生引擎配合。自带 API 模式继续直连，毋须注册；托管模式仅接收已授权的新中文语段。回放、编辑、复制、原音保存和外部输入仍归本机管理。托管服务异常时不把历史语音自动重传，也不向 BYOK 模型借用凭据。

**实际入口：** [在线版本和环境](https://saytile-cloud.vercel.app/v1/health)；[Vercel 项目](https://vercel.com/haohongfei2001-8529/saytile-cloud)；[生产环境变量](https://vercel.com/haohongfei2001-8529/saytile-cloud/settings/environment-variables)。这是独立项目；“Production”只表示该项目的稳定域名，不是现有 Mac 生产版。真实付费调用保持关闭。

## 部署与凭据

1. 只有取得独立零新增费用 Supabase 项目后才执行迁移。依文件名顺序应用 `supabase/migrations/*.sql`；不要使用其他产品数据库。Data API 开启，暴露 public RPC，不暴露 saytile；关闭匿名登录、开启邮件确认。邮件模板使用 `{{ .Token }}`，接入已验证发件域名和 SMTP，限制 OTP 发送频率。注册不发权益。Auth 的访问 JWT 短期有效，刷新令牌只留 Mac 钥匙串。邀请制阶段可关闭公开注册，只创建获准测试用户。
2. 在上述 Vercel 项目的 **Settings → Environment Variables → Production** 添加 `SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`、Sensitive 类型的 `SUPABASE_SECRET_KEY`。只向客户端返回 publishable key。禁止将运营密钥放入 Mac 或预览/开发环境；不使用 NEXT_PUBLIC 前缀设置秘密。
3. 凭据持有人在同一入口一次填写 Sensitive 类型的 `QWEN_API_KEY`、`OPENAI_API_KEY`，以及匹配的 `QWEN_WORKSPACE_ID`、`QWEN_REGION`（cn-beijing 或 ap-southeast-1）。首版服务协议为 [Qwen Message](https://help.aliyun.com/zh/model-studio/qwen-asr-message-websocket-api) 和 [GPT-6 Astra Responses](https://developers.openai.com/api/docs/models/gpt-6-astra)。轮换只重部署此网关。不得通过命令行参数、聊天、仓库或客户机传递运营钥匙。
4. 完成账户地域、费率和合同检查，设 `HOSTED_MARKETS` 为经过核准的国家代码逗号列表；未知或中国大陆 IP 禁止托管调用。原音及区域合规单独验收。未授权真实消耗前保持 `HOSTED_CALLS_ENABLED` 关闭，并保持数据库 control.enabled=false。两道开关都打开、用户有有效权益且有足够预留时才能调用。
5. 在批准的微额预算范围内设置数据库预算，再设 `HOSTED_CALLS_ENABLED=true` 并重部署一次；真实用户账号测试不写入公开证据。Vercel 域名、环境和返回 SHA 三者须匹配；相同 SHA 不为确认重复部署。独立验证数据恢复后再放行商业运营。

## 闭测权益与计费

在专属项目 SQL Editor / 受信运营会话用绑定参数执行下列语句；没有公共管理员路由。用户 UUID 来自 Auth，不能由客户端指定。预算使用**美元百万分之一**，不是账单或代币数。所有预留按全平台同一行加锁。按实际音频退款，服务商账单未归集则继续占用美元预留，不把未知记作零。

```sql
select public.st_grant(:uid,:milliseconds,:valid_until,:unique_audit_event,true);
select public.st_grant(:uid,0,now(),:revocation_event,false);
-- 配额与预算必须由运营根据合同和本次允许的总成本确定；新项目账本预设为关闭。
update saytile.control set asr_hold=:worst_35s_cost,review_hold=:worst_one_review,
 user_day_micros=:per_user_rolling_24h_cap,budget_micros=:authorized_lifetime_cap,enabled=true where singleton;
-- 立即停止新的消费；在线会话每五秒同时复核 Supabase 登录和权益，失效后关闭，不影响 BYOK。
update saytile.control set enabled=false where singleton;
select public.st_reconcile(:lease,:operation,:actual_micro_usd,:unique_provider_line);
```

35 秒预留覆盖 Mac 最长 30 秒语段及预卷。每用户最多两个活跃语音会话、两个同时进行的 GPT 请求、每分钟 12 次录音、每录音最多 16 次文本复核。重复录音不重复接单；复核只接受网关签发的、与账户/租约/文字摘要/稳定范围绑定的候选。网关硬截止 95 秒，早于函数的 180 秒配置；触发超时只影响该段。本机保留 journal，后续新语段独立处理。操作未明确结束、掉线或供应商金额缺失时保留预留，运营根据请求标识对账。超出单笔预留自动熔断；运营应在供应商账户另外设置可用的预算告警和额度约束，不把内部估算作为上游报价保证。变更模型或单价前先关闭开关，重新核算最大输入字节数和 8192 个输出 token（含推理）的费用上界。

Stripe 适配器默认关闭。商户启用前核验 [独立 macOS 分发](https://developer.apple.com/macos/distribution/) 和商户所在地规则；不处理银行卡数据。需商户授权后设置 `BILLING_ENABLED=true`、`PUBLIC_ORIGIN=https://saytile-cloud.vercel.app`、Sensitive 的 `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET`、固定 `STRIPE_PRICE_ID` 及 `STRIPE_PERIOD_MS`。Checkout 跳回及客户端按钮均不发权益；[签名账单事件](https://docs.stripe.com/billing/subscriptions/webhooks)经金额、SKU、到期和幂等校验后入账。订阅终止撤权，争议/退款冻结待核。首次使用 Stripe test mode 验证完整商户流程，live 模式另行批准。无商户时可使用经审计的手动权益，不创建收费订单。

## 隐私与地区

麦克风权限、托管上传同意、登录、权益为分开的条件。Vercel 实时转送中文 PCM 至对应阿里云地域，只把候选文字提交 OpenAI（store:false），不上传整个历史和用户草稿。网关不把语音和转写写入数据库、文件或日志；Supabase 存身份、账户、录音随机标识、用量/时间窗和记账事件；商户接受必要账单信息。store:false 不等于上游无任何保留：须以供应商账户的数据政策、地域、保留期和 DPA 为准。不可开启正文跟踪或把音频、令牌、签名证据发送到错误监控。账户删除须验证身份、撤销权益并按合法财务留存要求处理账本；本机原音由用户单独控制。

中国大陆未放行。[个人信息保护法第三十八、三十九条](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm)涉及出境路径、告知与单独同意；商用前须由运营方明确处理人、接收方联系方式、权利申请渠道、保留期限、DPA 和可销售地区，并完成 [OpenAI API 地域资格](https://platform.openai.com/docs/supported-countries)及用户所在地的实际直连验收。网关转发和代理网络连通不构成地域许可。未就绪时不在该地区售卖或启用模型调用。

## 复验与回退

运行 `npm ci --prefix cloud && npm test --prefix cloud` 和 `scripts/test-hosted-gateway.sh`。独立 PostgreSQL 多连接测试见 CI。`scripts/test-supabase-local.sh` 使用官方 Supabase CLI、隔离本地邮件及数据库演练实际 Auth / PostgREST；从未链接远端项目。机器测试只用合成数据。正式链路验收需在获得费用/音频授权后以一个授予权益和一个未授予权益的隔离账户执行，统计 20–30 分钟的实际首字/定稿 P50/P95、逐条响应、费用和失败率；与 BYOK 用同一授权音频对照。不得从模拟器推算这些值。

回退先关闭数据库开关和收费入口，保留账本；必要时切回 Vercel 前一已验证部署。不要为回退删除表、重置用户或清除 Keychain。Mac 保留配套的本地数据库及原音备份；v6 可回到 PR #13 的 v6 候选，v5 老版需恢复升级前的整套副本。检查签名和来源后在隔离目录演练，禁止对真实历史执行降级。
