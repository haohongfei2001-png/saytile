# Saytile 0.20（533）个人内测

已在原位安装并打开。安装文件、运行进程和 Launch Services 均只找到一份 Saytile。产品源码为 `7c0df4728b113c17297a0cded20472de4ffc3337`，签名应用与镜像通过 Apple 公证及 Gatekeeper。官网仍分发 0.18（492），0.20 的公开更新源暂未上架。[安装与回退](RELEASE.md) · [机器收据](../../../evidence/internal-0.20-533/release.json)

| 工作项 | 状态及证据 |
| --- | --- |
| 497 → 533 原位安装 | PASS。统一名称、白底图标、资料身份、签名要求及已有更新渠道均已核对。[版本来源](BASELINE.md) |
| 待命、段落和档案 | PASS。可记住明确启用的持续待命，主动暂停和退出优先。自然段贯穿输入板、复制、编辑与回听。[原生验收](ACCEPTANCE.md) |
| 本地中文识别 | PASS。固定 420 条 CER 8.53%。高负载长句超过两秒才出现新字仍可复现，此项 FAIL。[质量数据](QUALITY.md) |
| 安全输入与其他窗口 | PASS。AppKit、WKWebView、Chrome 使用独立窗口验证，真实写入保持一次。窗口拖动后可以恢复边界；全屏避让与浮板位置恢复已验。系统在全屏往返后保留外部窗口原归属的情形仍为 BLOCKED。[缺陷记录](ISSUES.md) |
| iCloud 和 iPhone | PASS 的范围为离线往返与 iOS Simulator。真实 iCloud 三端往返 BLOCKED。[详情](ACCEPTANCE.md) |
| 用户反馈 | PASS 的范围为本地原生控件、断网草稿、恢复和受控传输。真实私有工单送达 BLOCKED。 |
| Nearpane | 独立宿主的共享语音路径及其原生 CI 通过。首次显示和完整产品一致性仍有局限。[独立 PR](https://github.com/haohongfei2001-png/nearpane/pull/11) |
| 发布 | 本机候选 PASS。公开 0.20 Beta 暂缓。此次未合并或发布稳定版。 |

产品源码通过七项 GitHub 检查。420 条加速录音绑定识别修复源码。固定 15 条原速和五条历史难例均已在与本机安装相同的 533 签名二进制上复测。账户事项与下一次工程起点见[交接](HANDOFF.md)。
