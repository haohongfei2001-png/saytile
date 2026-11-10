# Saytile 本机识别工程候选

[唯一 DMG](Saytile-1.0.0-rc.2-local-asr.3-arm64.dmg) · [SHA-256](SHA256SUMS.txt) · [签名和 Gatekeeper](../../evidence/local-asr/delivery/install-3.txt) · [隔离升级、回退收据](../../evidence/local-asr/delivery/upgrade-final.json) · [原生窗口录像](../../evidence/local-asr/delivery/live-panel.mp4)

Apple Silicon；继承 RC2 的 macOS 26 或更新要求。本包在 M5、macOS 27.0 上安装运行。应用内嵌清洁源码版本 **e7c4ac86231090ef820178d4543db745944af4a4**。外部模型在选择后下载到应用支持目录；安装包没有权重，也不要求 Python、Xcode 或 Conda。Apple 的本机语言资源由系统管理。

此为独立 Draft PR 的工程交付，不是公开发行。App、识别进程、动态库和 DMG 已签名。Gatekeeper 评估为 **rejected / Unnotarized Developer ID**。没有将此结果算作公众安装通过。当前无需用户安装、录音或调整系统安全设置。

工程验证从只读挂载的 DMG 将 Saytile.app 复制到临时 Applications，退出并卸载镜像，以独立数据目录启动。正式应用标识与 RC2 相同，勿覆盖生产 RC1。获准升级时，应先退出应用，备份整个应用支持目录（含 Audio、SQLite 及旁文件、LocalModels）和原安装包。此版保持 schema 6；与前一份 schema 6 整合候选的往返替换已在隔离副本中验证。回退更旧的 schema 必须连同对应备份还原；升级后新增的数据另存，不能将新库硬交给旧版。

本机使用：设置 → 识别服务 → 服务来源选“本机”，在“本机识别”中选“自动推荐”。Apple 语言资源准备好后使用系统实时路径；缺少资源且已下载轻量 Streaming Paraformer 时使用后者。手动模型选择只影响下一段；标记“分段重识别”的模型只处理已保存原音。可选 GPT-6 文字核对需要分别提供凭据和授权；离线 ASR 和原音保存无需这两项。
