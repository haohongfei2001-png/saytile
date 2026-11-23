# Saytile

**自然开口，随时取用。**

Saytile 是 Apple Silicon Mac 上的本地中文语音输入工具。Qwen 0.6B 在讲话过程中显示临时文字，停止后完成原音定稿；确认后的短语可逐步写入用户选定的应用。文字、手动修改和原音分别保存，不依赖网络。

**1.0.0（572）已正式发布**：[官网下载](https://saytile.com/#start) · [GitHub Release 与校验文件](https://github.com/haohongfei2001-png/saytile/releases/tag/v1.0.0)。Developer ID 已签名，尚未公证，首次安装可能需要系统单 App 打开确认，见[安装说明](docs/V1-INSTALL.md)。发行状态、原始失败与已知限制见 [STATUS](STATUS.md) 和 [验收记录](docs/delivery/release-100/ACCEPTANCE.md)。

## 使用

- 需要 Apple Silicon、macOS 26 或更新系统。首次联网下载约 713 MB 的 Qwen 模型，随后可离线使用；没有 API Key 或订阅要求。模型准备期间可使用系统 Apple 本地识别，具体状态在设置显示。
- 语音板只有复制和语音状态两个常驻按钮。右侧按钮暂停/恢复收音；菜单栏点击展开菜单，单独控制语音板显隐。
- 连续文字可选择、编辑、复制；自然停顿形成段落。无选区复制当前段落，档案按相同段落组织，支持搜索、星标、回听和重识别。
- 自由记录保存在自己的档案。直接输入须授予辅助功能权限并绑定目标；普通复制不需要辅助功能权限。
- 直接输入只追加已确认的短语。目标、光标、选区或用户内容变化时停止自动操作。EOS 的局部修正仅在完整目标内容和所属范围仍可验证时进行，否则保留到档案。Saytile 不按回车、不发送消息、不重试不确定的写入。
- 临时预览可能修订；数字、否定词和名称仍需用户阅读确认。模型不可用或识别失败时保留原音和已有文字，允许重试。

## 安装、更新和资料

见 [安装与回退](docs/V1-INSTALL.md)。正式 1.0 使用现有公开中文版本的 Bundle ID `app.saytile.mac.mandarin-candidate`，这个历史内部标识不会影响产品名称。

0.18、0.20（533）与 1.0 延续相同资料目录 `~/Library/Application Support/Saytile Mandarin Candidate`、Keychain 服务和更新通道。旧 RC1 的 `app.saytile.mac` 及 `Saytile` 资料目录保持独立，不会静默移动或覆盖。不要删除旧资料来升级。

原音默认保留至手动删除。仅删除原音会保留文字和历史修订。iCloud 跨设备同步、尚未配置的反馈服务和云端识别不属于本地默认承诺；未经明确授权不会上传录音。

## 源码构建和测试

```sh
scripts/build-app.sh debug
scripts/test-app-model.sh
scripts/test-native.sh
python3 scripts/verify.py
```

构建会获取固定版本的 Sparkle、MLX/原生运行库，不捆绑模型权重。完整 Swift Testing/XCTest 需要完整 Xcode；Command Line Tools 构建成功不等于完整测试通过。原生测试使用隔离资料目录；不要把真实档案用于故障注入。

正式签名构建与 DMG 步骤见 [发行流程](distribution/README.md)。历史 #52、#53、#54 原始证据继续保留；整合文件来源见 [INTEGRATION.json](docs/delivery/release-100/INTEGRATION.json)。

## 产品与来源

[唯一主面板设计](docs/SAYTILE-V1-COMPACT-TRANSCRIPT-PANEL-DESIGN.md) · [批准图标](design/approved/app-icon/README.md) · [第三方许可](THIRD_PARTY_NOTICES.md) · [官网源码和批准范围](website/README.md)

主语音板没有 Logo 或产品名，白色轻透面板、连续文字和两个按钮保持原定设计。紫色与黑色品牌是已有设置选项。旧 prototype 与 archive 是历史材料，不能替代当前原生界面验收；archive 原件只读。V2 轻声、V3 个人词库不在 1.0 范围内。
