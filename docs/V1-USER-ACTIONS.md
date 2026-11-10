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

2026-11-10 · No engineering test or recording required from the user. Approved organization must have a zero-increment independent slot before remote Supabase creation. Then owner enters secrets once in the named Vercel project and approves a bounded real usage test. Merchant and notarization authorizations are separate release gates.

本机实时识别的工程验收使用固定许可样本，不需要用户录音或提供密钥。模型按需下载，Apple 语言资源由系统管理。

Apple 中文资源已在本机准备，七路样本均由工程自行运行。实际面板、下载器和归档验证不使用私人麦克风。

本机录音的 GPT-6 文字核对需要用户自带 OpenAI 凭据并显式开启独立文字授权。开发验收使用离线回归替身，真实付费调用未运行。

隔离的主板验收使用公开语料驱动原生音频缓冲，无需麦克风授权。

该预览停滞由工程使用固定真人语料复现并复验，不需要用户协助。

工程录像仅捕获隔离窗口。无需个人录音、桌面授权或操作；公开安装仍待发行方 Apple 公证。

本轮无需用户操作。下载、出字、模型切换、原音失败保护、升级及隔离录屏已由工程处理。仅将发行方 Apple 公证、未来真实云端凭据/费用授权和可选真人物理麦克风体验保留为独立事项。
