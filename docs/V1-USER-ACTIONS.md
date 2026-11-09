## RC2 连续时间轴整合候选

本轮工程复核无需用户录音或操作。云端联调仅在专用凭据、上传与计费授权就绪后由联调负责人执行。[整合及发布边界](V1-RC2-TIMELINE-INTEGRATION.md)

# 连续时间轴独立预览

没有需要用户参与的开发测试。无选区复制范围暂按最新活动组。未来进入真实云端验收时，由授权人一次配置所选 ASR 与 OpenAI 凭据和上传／费用授权。公证由发行方处理。 [完整交付及验收](V1-CONTINUOUS-TIMELINE.md)

# no-api.10 授权事项

目前没有需要用户执行的开发测试。

- **标准安装分发**由发行方完成。App 和 DMG 已使用 Developer ID 签名。发行方需为 Saytile 配置有权提交 Apple 公证的身份，提交冻结镜像、装订回执并复查带下载隔离属性的 Gatekeeper，再发布新散列。
- **真实云端接入**由账户所有者在原生设置中完成。选择讲话语言，在「AI 识别 → 连接识别服务」中保存所选 ASR 与 OpenAI 两把凭据。中文 Qwen 还需要账户对应地域及 Workspace。分别同意语音或候选文字的处理，并确认内置合成样本的上传和费用范围。密钥仅填入 App 的安全字段。
- **真实质量验收**使用得到授权的既有人声音频。服务接通后再测识别误差和确认延迟。

[原生接入步骤与调用上限](V1-RC2-CONNECTION-SETUP.md) · [机器验收](V1-NO-API-DELIVERY.md)


2026-11-10 · Saytile Cloud: Supabase selected organization quoted USD 10/month. Free-only creation blocked. No merchant/provider calls approved.

2026-11-10 · Saytile Cloud: Vercel authorization succeeded; no further CLI login needed. Secure project settings and the free-only database blocker are recorded in cloud/README.md.

2026-11-10 · No customer action for the ongoing isolated authentication, packaging and upgrade rehearsals.

2026-11-10 · No customer testing or real audio needed for these fixes; the free hosted database allocation remains the external prerequisite.

2026-11-10 · Vercel ingress and native consent retests are handled by engineering. No approval needed.

2026-11-10 · No changes to user actions. Gateway can remain live with model calls disabled while waiting for free Supabase capacity.
