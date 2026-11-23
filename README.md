# Saytile

macOS 原生中文语音输入：连续文字流、可编辑档案、原音回听与安全增量输入。

本分支是 **0.21（564）发行候选**，目标为 main。当前裁决 **HOLD**；尚未公开发行，不替换正在使用的 0.20（533）。当前公开官网及 Sparkle 更新源保持原版本，候选与公开下载不能混为一谈。

- [统一状态](docs/delivery/release-021/STATUS.md)
- [最终验收与发布阻塞](docs/delivery/release-021/ACCEPTANCE.md)
- [架构与发行来源](docs/delivery/release-021/ARCHITECTURE.md)
- [安装、升级与回退](docs/INTERNAL-INSTALL.md)
- [本轮证据](evidence/release-021)
- [正式官网](https://saytile.com/)

每段只运行一个本地 ASR；Qwen 实时预览与最终文字分别处理。音频独立保存，识别失败不删除录音。外部应用仅接收被确认的文字，不自动发送。用户修改不会被迟到结果覆盖。无需 API 即可使用本地识别。

iCloud、Saytile Cloud、BYOK 和反馈连接保留既有代码边界；未获授权或未完成真实验收的服务不会宣称可用。不承诺尚未验证的跨设备恢复或云端质量。

## 构建与测试

需要 macOS 26+、Apple Silicon、Swift 6 工具链；完整自动测试在完整 Xcode 的 macOS CI 执行。`scripts/build-app.sh` 构建原生 App；`scripts/test-native.sh` 运行全部 Swift 测试。第三方模型按需下载，模型及运行库来源见 `THIRD_PARTY_NOTICES.md`。

正式候选保持现有 Bundle ID `app.saytile.mac.mandarin-candidate` 和资料路径。使用 `SAYTILE_MANDARIN_CANDIDATE=1` 与既有 Developer ID 执行 `scripts/package-beta.sh`。`packaging/BUILD_NUMBER` 独立于 Git 提交数量，保证主线整理后更新版本仍单调增加。不要把默认开发构建作为已签名、公证的候选交付。

本分支从最新 main 选择性纳入 PR #49、#50、#51 的产品代码及必要依赖；没有合并其历史提交链、旧安装包或全部实验资料。完整原始证据保留在原 PR 和 `codex/release-021-closure-work`，选择清单见 `evidence/release-021/curation.json`。
