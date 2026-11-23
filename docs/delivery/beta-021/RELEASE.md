# 0.21（557）安装与签名边界

只交付一个新候选 DMG，不替换当前 533，不在 Applications 增加体验版或改变资料身份。

| 项目 | 值 |
| --- | --- |
| 包 | `Saytile-0.21-557-arm64.dmg`，64,513,466 字节（61.52 MiB） |
| 产品源码 | `9aace8f5b0d7082bd67d2e9b1b6e1db6dcf05883`，构建树干净 |
| DMG SHA-256 | `7e44a00ba5e1ae4f47b70b37360929dd658b1b9f17a7ce745339156d873e0f83` |
| 主程序 SHA-256 | `10895f5a01c615d408ac7fb95b9aac98ff2982638979bd11590d135e94fb6d33` |
| Bundle ID | `app.saytile.mac.mandarin-candidate`，沿用当前身份 |
| 签名 | Developer ID 团队 ZB9D4T66QB；Hardened Runtime、安全时间戳、严格签名 PASS |
| 公证 | BLOCKED：尚无可用 notarytool 授权配置，未提交新包 |
| Gatekeeper | 实测 rejected / Unnotarized Developer ID；stapler 无票据 |

已从只读挂载的 DMG 提取同一二进制，在显式临时目录完成实际启动、文字、UI、资料、更新和回退。这不是从网络新下载后通过 Gatekeeper 的正式发行安装；没有删除 quarantine 或改变系统安全。[签名收据](../../../evidence/beta-021/final/signature.json) · [完整构建日志](../../../evidence/beta-021/final/package-build.log.gz)

初次打包时间戳网络失败日志保留在二轮证据，当前包已取得验证时间戳。公证装订可能改变包哈希，届时须新增明确收据，不悄悄替换本哈希。

## 升级与回退实测

533→557→533→557 使用两份合成可解码 WAV、四个修订、两份编辑稿及九张表；逐步检查逻辑表、原音 SHA、编辑优先稿、段落、收藏、偏好和模型标记。Keychain 仅验证服务名与签名身份，无读取密钥。[回退](../../../evidence/beta-021/final/rollback.json)

真实 AppUpdateController→Sparkle 安装器→无参数重启，临时 loopback 更新源及临时签名密钥：损坏包拒绝、有效包安装，SQLite、原音、偏好和模型标记保持。用户驱动为隔离 fixture，普通 Sparkle 对话框人工点击 NOT_RUN。没有改公开 appcast。[更新](../../../evidence/beta-021/final/update/receipt.json)

取得公证后先核验 Apple 结果、装订和新 DMG Gatekeeper，再允许原位替换 `~/Applications/Saytile.app`。更换前正常退出并保留原 App；不删除 Application Support、偏好、模型或 Keychain。回退仅正常退出并换回 533 App，不覆盖数据库。旧资料空间合并仍走现有显式副本迁移，不扫描私人目录。
