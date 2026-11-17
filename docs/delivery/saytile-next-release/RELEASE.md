# 0.20（533）安装、更新与回退

2026-11-17，个人内测已经原位安装并打开。唯一入口为 `~/Applications/Saytile.app`。Launch Services 的实际注册、系统运行进程和两个应用目录的检查均只返回此路径。系统显示名称为 Saytile，紫色字形沿用已批准的十个尺寸，图标源底色为白色。Finder 仍会应用系统光照。[交付收据](../../../evidence/internal-0.20-533/release.json) · [安装后 Finder 图标](../../../evidence/internal-0.20-533/Finder-icon.png)

| 项目 | 实际结果 |
| --- | --- |
| 产品源码 | `7c0df4728b113c17297a0cded20472de4ffc3337`，干净树。后续验收提交更新收据、文档及隔离截图程序 |
| 安装镜像 | `dist/internal-0.20-533/Saytile-0.20-533-arm64.dmg`，64,286,329 字节 |
| SHA-256 | `e2739094eef9d58eb12401ecbd302d81152ca9bae60e3dd43435aef33efc8dcb` |
| 安装程序 SHA-256 | `d711d1cab97d0ff20e23129269b8d72989db2e5258f659d49276f77cf9ab4737` |
| 签名 | Developer ID 团队 ZB9D4T66QB。逐一核实 10 个 Mach-O 的签名、Hardened Runtime 与安全时间戳 |
| Apple 公证 | App `8122bb55-6a7d-4eff-ac09-b1dd1b6b13c9` 和 DMG `73d60b67-5e1d-4668-91cb-ad1c06372d64` 均 Accepted |
| Gatekeeper | DMG、只读挂载的 App 和安装后的 App 均为 `accepted / Notarized Developer ID` |
| 回退镜像 | `dist/internal-0.19-497/Saytile-0.19-497-arm64.dmg`，`517258571cb48edc3b3252b57bc9cf8544594426639bf7bde0dfd83129562a56` |
| iPhone Simulator 候选 | `dist/internal-0.20-533/evidence/reader/SaytileReader-Simulator.zip`，SHA-256 `659ffc9ca64d707b4611dd3c03304fcc7617b60c9da56e576f0c88e135333de2` |

Apple 的命令行工具为 App 取票时遇到 TLS 中断。同一票据经 HTTPS 从 Apple 取得，用已验证开发者签名与发布校验和的 rcodesign 0.29.0 装订在 App 中，并逐字节核对。DMG 由 Apple stapler 装订和验证。正常 Gatekeeper 已分别核验镜像和程序。没有调整系统安全设置。[Apple 公证](../../../evidence/internal-0.20-533/app-notary-info.json) · [镜像公证](../../../evidence/internal-0.20-533/dmg-notary-info.json) · [逐文件签名](../../../evidence/internal-0.20-533/signatures.json) · [工具作者文档](https://gregoryszorc.com/docs/apple-codesign/stable/apple_codesign_rcodesign_notarizing.html)

## 本机升级

在已签名 497 和 533 的临时合成档案上完成四步回退演练后，复核原包哈希、被测二进制、Bundle ID、指定签名要求、Keychain 服务名、资料和更新配置。安装时仅在原应用路径原子交换 App，通过空目录启动探针，再正常打开，核实实际运行路径。本机准确日志位于镜像旁的 `evidence/`。验收过程没有直接打开个人档案、录音或密钥。[四步演练](../../../evidence/internal-0.20-533/rollback-497.json)

如需回退，正常退出 Saytile，打开留存的 497 镜像，将其中 `Saytile.app` 替换至原位置再打开。无需删除应用支持目录、偏好或缓存。0.12 的原资料空间保持独立。明确需要合并时，内置迁移命令只读取指定的两份副本，在全新目录生成结果，并核对 WAV、文字版本和完整性。[交接说明](HANDOFF.md) · [迁移实测](../../../evidence/internal-0.20-533/merge.json)

## 公开渠道

官网匿名入口仍提供 0.18（492），已下载的文件为 64,972,638 字节，SHA-256 `654b08e926d90c88e0cb05ff4a5c116aa6c87c6cd59f7d71c24ca028c0d5f933`。533 的原生设置已成功校验真实公开 Sparkle feed 的签名，其中有 0 项更新。此次仅交付本机内测。高负载文字停顿尚在，真实 iCloud 恢复和反馈送达亦未具备全链路结论。[官网下载](https://saytile.com) · [真实更新收据](../../../evidence/internal-0.20-533/sparkle/receipt.json)
