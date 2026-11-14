Saytile 内测 0.18（492），现有中文识别候选的公开下载包。此版本仍属内测，不是正式稳定版。

## 下载与系统要求

- Apple Silicon（ARM64），macOS 26.0 或更高；不支持 Intel Mac。
- DMG：64,972,638 字节，约 65 MB；不包含大型模型权重。
- 首次使用需要麦克风授权及网络准备约 713 MB 的 Qwen 本地中文模型；下载期间尝试 Apple 本地识别，必要时另行准备系统语言资源。资源就绪后可离线使用，无需 Saytile 账号或 ASR API Key。
- 此内测不提供已接通的 Saytile Cloud 正式服务，不承诺 iCloud 同步已可用。

## 安装与签名限制

App 与 DMG 已通过 Developer ID 签名校验，Team ID `ZB9D4T66QB`。**尚未提交 Apple 公证；实际 Gatekeeper 检查为 `Unnotarized Developer ID`，未获放行。** 本机工程启动成功不能代替互联网下载后的安装验收。如果 macOS 阻止打开，请等待完成公证的版本，不需要关闭 Gatekeeper 或修改系统安全设置。

DMG 内为 `Saytile 中文识别候选.app`，Bundle ID `app.saytile.mac.mandarin-candidate`。这个内测身份与旧 `Saytile.app` 的原音、文字、设置、Keychain 和模型缓存分开保存；不会自动导入旧版档案。已有相同身份的中文候选升级沿用其资料。不建议删除任何旧资料目录。

## 本版内容与验证

继承自然段落、段落复制、现有本地中文识别及已批准的原生界面，新增签名校验的应用内更新。可在菜单或「关于」中检查更新；发现更新不会自动安装。当前更新源尚无后续版本。

- 最终源码：`012999c2018f591f3cf9a529e4c0ae81e7b81f21`，[PR #44](https://github.com/haohongfei2001-png/saytile/pull/44)。该产品 PR 保持 Draft，本次官网上线不合并其产品源码。
- 现有最终 CI 5/5；532 项 Swift Testing、183 项 AppModel 检查及 18 项打包配置检查通过。
- 已完成隔离签名宿主的升级、损坏包拒绝、重启和数据保留验证；不冒称用户真实语音质量验收。
- Mac 合盖期间物理麦克风现场讲话未验收，标准 Sparkle 弹窗逐按钮操作未运行，公证分发尚未通过。
- [完整产品验证记录与限制](https://github.com/haohongfei2001-png/saytile/blob/93444af132866b1282895817b04c10e3f809b2fa/evidence/in-app-updates/DELIVERY.md)

## 文件校验

`Saytile-0.18-mandarin-arm64.dmg`

SHA-256：`654b08e926d90c88e0cb05ff4a5c116aa6c87c6cd59f7d71c24ca028c0d5f933`

同页提供 SHA256SUMS.txt。该安装包与此前本机验收的 0.18（492）逐字节相同；本次未重新编译、重新签名或修改 App。
