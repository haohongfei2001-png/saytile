# Saytile 1.0.1（577）— 签名候选，发行 HOLD

产品源码 `3e1cc6961df4da01a1c52310755a7dd215ef4310`，SourceDirty=false；Draft PR #56面向main。已安装0.20（533）和个人档案/录音/密钥不变，未合并或发布。

## 已完成

- 首次模型准备页只展示一次；说明本机识别、下载体积、麦克风及可选辅助功能权限。拒绝麦克风后的恢复入口、正式版本展示已修复。
- AX未知角色、页面通信/短批次读取正确分类；已知目标/用户选区/只读/敏感字段拒绝优先。协调器、单次写入、两次完整证明、范围和零自动发送保护不变。页面28+role21+witness16场景通过。
- 产品SHA 3e1cc69完整native、584项Swift Testing与30项XCTest（零失败）、真实六类前台输入及标准Sparkle窗口通过。独立brand清单原FAIL保留；最终全检查等待刷新已审查源码清单后的CI，不冒称旧run全绿。
- 原速15段CER8.10%，420段8.5344%，440样本最终稿和状态新旧一致；5个失败子段原音保留。完整测量绑定574；577识别/存储对象相同，最终包另验38.8s原生实时出字。
- 最终577：56次原生控件操作、4场景真实截图；18项存储故障、0.18/533升级回退、只读DMG离线安装和篡改拒绝通过。
- 572→577真实Sparkle安装/回退、签名说明、坏包拒绝、六模型文件SHA/mtime保留，以及ZIP/feed独立公钥验证通过。生产源未启用新版本。

## 裁决与限制

**HOLD。** 缺现成公证授权，App/DMG实测 `Unnotarized Developer ID`。性能长尾尚未根治：原速候选首字P95 2.126s，原长句最大可见间隔3.085s；后续三对不构成CPU/长尾根治。原Chrome底层AX原因UNKNOWN，保持原失败，不承诺所有网页异常消失。

合盖麦克风、8GB实体Mac、真实断电NOT_RUN；CI kernel sleep因虚拟硬件BLOCKED。iCloud/私有反馈未启用，不宣传跨设备能力。

最终DMG `7fec71094a5ecc325b2991426dc8347ec0f6f77a9944bbeb96604a32fc514b78`，64,577,002字节，`dist/1.0.1/Saytile-1.0.1-arm64.dmg`。

[完整验收](docs/delivery/release-101/ACCEPTANCE.md) · [机器收据](evidence/release-101/DELIVERY.json) · [性能及失败](docs/delivery/release-101/PERFORMANCE.md)。

## 最小外部依赖

账户持有人仅需在本机为现有Team ZB9D4T66QB配置一次notarytool授权，不把密码发送到聊天。之后仍须真实公证Accepted、装订、更新重新签名、Gatekeeper与下载验收，才能合并和公开发行。缺此授权不伪造成功，也不要求用户进行开发测试。
