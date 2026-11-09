# Saytile V1 RC2 无 API 冻结候选

产品源码 `5639058e6b178027861b18cc0521387487c919d5`。安装包为 Apple Silicon / macOS 26+ 的 `1.0.0-rc.2-no-api.10`。后续收据单独提交。实际系统边界与最新结论以本文件及[机器证据](../evidence/no-api10/final/)为准。

[下载唯一候选 DMG](../deliverables/no-api.10/Saytile-1.0.0-rc.2-no-api.10-arm64.dmg) · [SHA-256](../deliverables/no-api.10/SHA256SUMS.txt) · [安装及回退](V1-INSTALL.md) · [API 接入](V1-RC2-CONNECTION-SETUP.md)

完整 Xcode 26.6 在此源码上运行了 401 项 Swift Testing，通过 401 项，失败和跳过均为 0。独占前台的 WKWebView、NSTextView、TextEdit 已通过。已用 Developer ID 签署 App 和 DMG，并验证实际 RC1 和 no-api.9.1 的隔离升级和回退。普通 Gatekeeper 拒绝未公证包。两小时持续采集、签名包常驻及独立安装包控件的最终收据待归档。真实云端状态为 NOT_RUN。
