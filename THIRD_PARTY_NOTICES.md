# 第三方与许可证边界

本交付没有打包 Apple SDK、语音模型权重、FluidAudio/WhisperKit/GRDB 源码或字体文件。

历史研究中的组件许可描述作为历史信息保存。正式工程需要对所选具体版本的代码、模型权重、依赖和分发条件分别复核。本交付不替代许可证审查。

公开仓库与授予开源许可证不是同一决定。本轮未添加 MIT/GPL 等项目许可证，不替用户作出新的开源授权。

## 原生 V1 已使用

- Apple AppKit / SwiftUI / AVFoundation / Speech / CoreAudio / ServiceManagement：系统框架，App 未包含 SDK 或系统语音模型；语言资源由 Apple AssetInventory 管理。
- SQLite：调用系统 libsqlite3；SQLite 属公有领域，不另捆绑二进制。
- WebRTC VAD：代码位于 `Sources/CAudio/webrtc/`，来自 wiseman/py-webrtcvad 的 vendored WebRTC；完整 BSD 许可及 wrapper MIT 许可见 `Sources/CAudio/WEBRTC-LICENSE.txt`，同时随 App Resources 分发。
- 引入来源包：`https://codeload.github.com/wiseman/py-webrtcvad/tar.gz/refs/heads/master`（2026-11-06 获取）；SHA-256 `4d585f73cdfac59e3df049745432079d09b896cef7878f4055f96ec43d01d211`。工程直接固定提交全部所需源码，构建不再拉取可变 master。
- `AudioRing.c`、桥接 VAD 包装器与 Swift 原生模块为 Saytile 本轮实现。
