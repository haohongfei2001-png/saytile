# Saytile V1 整合候选

此目录提供唯一的本轮 DMG，适用于 Apple Silicon、macOS 26 及以上。[SHA-256](SHA256SUMS.txt) · [验收报告](../../docs/V1-INTEGRATED-CANDIDATE.md)

打开 DMG，将 Saytile 拷贝到“应用程序”。工程演练安装在独立目录。当前包已用 Developer ID 签名，尚未提交 Apple 公证。Gatekeeper 仍拒绝从互联网下载的公开分发包。

首次开启收音后，按系统提示允许麦克风及必要的本地识别资源。本机模式不需要 API 密钥。辅助功能权限用于用户主动绑定的跨应用直接输入。复制可直接使用。

升级前退出 Saytile，并保留旧应用及对应的整个 Saytile 资料目录。新版沿用现有应用与 Keychain 身份。回退时退出程序，恢复旧应用和配套的升级前备份。旧应用会拒绝 v6 资料库。保留新版资料副本，以免丢失升级之后的新讲话或编辑。
