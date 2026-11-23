# 0.21（563）安装与签名边界

交付一个新候选 DMG，当前533保持原位；未在 Applications 增加体验版，未改变资料身份。**HOLD：尚不能作为可公开分发的安装包推广。**

| 项目 | 值 |
| --- | --- |
| 包 | `Saytile-0.21-563-arm64.dmg`，64,500,811字节（61.51MiB） |
| 产品源码 | `8514fea5d45a778aae84854db9b139f7a1fbb85b`，构建树干净 |
| DMG SHA-256 | `a77e9bcd2447cee254f8dac9dfc1a797318ab424d1e220e06e9ea535d646a1c2` |
| 主程序 SHA-256 | `6bdc43a58c22af783a061ed875b7f2b1f11c747574929cd2a8cb6cd1c890a8eb` |
| Bundle ID | `app.saytile.mac.mandarin-candidate`，沿用当前身份 |
| 签名 | Developer ID 团队ZB9D4T66QB；Hardened Runtime、安全时间戳、严格签名PASS |
| 公证 | BLOCKED：尚无可用notarytool授权配置，未提交新包 |
| Gatekeeper | 实测rejected / Unnotarized Developer ID；stapler无票据 |

从只读挂载DMG提取的同一二进制已在显式临时目录完成启动、文字、UI、资料、更新与回退。此为真实原生工程运行，**不是网络下载后通过Gatekeeper的正式发行安装**。没有删除quarantine或改变系统安全。[签名收据](../../../evidence/beta-021/final-563/signature.json) · [完整构建日志](../../../evidence/beta-021/final-563/package.log.gz)。

## 升级与回退实测

533→563→533→563使用两份合成可解码WAV、四个修订、两份编辑稿及九张表，逐步检查逻辑表、原音SHA、编辑优先稿、段落、收藏、偏好及模型标记。Keychain只验证服务名与签名身份，未读取真实密钥。[回退收据](../../../evidence/beta-021/final-563/rollback.json)。

真实AppUpdateController→Sparkle安装器→无参数重启，使用临时loopback源和临时Ed25519密钥：损坏包拒绝、有效包安装，SQLite/原音/偏好/模型标记保持。用户驱动为隔离fixture；普通Sparkle弹窗人工点击NOT_RUN。未改公开appcast，未公开上传安装包。[更新收据](../../../evidence/beta-021/final-563/update/receipt.json)。

取得公证后，由工程核验Apple结果、装订及新的DMG Gatekeeper。装订可能改变包SHA，须新增明确收据；不能悄悄替换本哈希。只有发布条件通过才原位升级唯一的`~/Applications/Saytile.app`：先正常退出并保留原App，不删除Application Support、偏好、模型或Keychain。回退仅退出并换回533 App，不覆盖数据库。需要旧档案合并时，继续使用现有显式副本迁移，不扫描私人目录。
