# Saytile V1 RC2 · no-api.9

Apple Silicon / macOS 26+ 的工程候选。[确切运行源码 `dc26fe3c`](https://github.com/haohongfei2001-png/saytile/commit/dc26fe3c59ba55994d29e99ada8d2f0b49ad9886)。按[上传原稿的实测几何](../../design/approved/original-reference-20261107.measurements.json)保留 344×234 pt 卡片和 408×298 pt 生产窗口。稳定 RC1 不变。

- [候选 DMG](Saytile-1.0.0-rc.2-no-api.9-arm64.dmg)，SHA-256 `0bd16e511f3a1cf65a3618443ef3c498ca517786aa4ad07a0226451a0c2b449d`，大小 2,556,244 字节。
- 解包 App 可执行文件 SHA-256 `cb3b7a38dae90fccd323b57ee746baedbfcb43b457e0b30dbdcbaedffd35ed00`。严格代码签名校验通过；ad-hoc，未 Developer ID 公证，本机[Gatekeeper 执行策略拒绝](../../evidence/no-api9/final/gatekeeper.json)。该工程包还不能作为面向普通下载用户的公开发行版。
- [安装、备份与回退](../../docs/V1-INSTALL.md) · [本版证据](../../evidence/no-api9/) · [云端连接入口](../../docs/V1-USER-ACTIONS.md)。

未调用真实云服务或上传私人录音。实际真人质量及相对最强单模型的收益未测。
