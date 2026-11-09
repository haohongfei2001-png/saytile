# Saytile V1 RC2 无 API 冻结候选

产品源码 `53f65d32aff3a7f82ea929591b8202a82aa4ee97`。安装包为 Apple Silicon / macOS 26+ 的 `1.0.0-rc.2-no-api.10`。后续收据单独提交。实际系统边界与最新结论以本文件及[机器证据](../evidence/no-api10/final/)为准。

[下载唯一候选 DMG](../deliverables/no-api.10/Saytile-1.0.0-rc.2-no-api.10-arm64.dmg) · [SHA-256](../deliverables/no-api.10/SHA256SUMS.txt) · [安装及回退](V1-INSTALL.md) · [API 接入](V1-RC2-CONNECTION-SETUP.md)

截至首批证据提交，完整 Xcode 26.6 已对该 SHA 执行 401 项 Swift Testing，401 项通过、0 项失败、0 项跳过。独占前台的 WKWebView、NSTextView 和 TextEdit 三种目标已通过。原音和数据库异常恢复、两种麦克风路由以及 RC1 和 no-api.9.1 的隔离升级回退已通过。两小时持续采集已启动，结论待该次运行结束。

系统睡眠请求在托管 VirtualMac 返回 71；最终 DMG 和 App 均已用 Developer ID 正式签名；普通 Gatekeeper 返回 Unnotarized Developer ID，公开分发 BLOCKED。独占 Mac 已经通过专用虚拟麦克风验证讲话中收到睡眠通知时落盘、唤醒后重新采集及手动暂停保持。真实服务商连接、云端识别、准确率和确认延迟均为 NOT_RUN。
