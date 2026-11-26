# Saytile

**自然开口，随时取用。**

Saytile 是 Apple Silicon Mac 上始终待命的个人语音表达面板。自然讲话，Qwen 0.6B 实时呈现文字，短暂停顿后仍接续同一自然段；需要使用时，一键复制完整自然段。文字、手动修改和原音分别保存在本机。

**1.0.0（572）已正式发布**：[官网下载](https://saytile.com/#start) · [GitHub Release 与校验文件](https://github.com/haohongfei2001-png/saytile/releases/tag/v1.0.0)。Developer ID 已签名，尚未公证；签名不代表 Gatekeeper 已放行，见[安装与发行边界](docs/V1-INSTALL.md)。发行状态、原始失败与已知限制见 [STATUS](STATUS.md) 和 [验收记录](docs/delivery/release-100/ACCEPTANCE.md)。

**1.1.0（578）正在开发，尚未发行。** [开发分支](https://github.com/haohongfei2001-png/saytile/tree/pro/release-110)以 [PR #56](https://github.com/haohongfei2001-png/saytile/pull/56) 的 1.0.1（577）候选为基础，保留首次使用、输入确认及更新修复，集中完善自然段、完整复制和常驻体验。1.0.1 无需另行发行；[原候选验收与限制](docs/delivery/release-101/ACCEPTANCE.md)保留为历史记录，不代表新候选已通过实机验收。官网和公开更新源仍指向已发布版本。

## 使用

- 需要 Apple Silicon、macOS 26 或更新系统。首次联网下载约 713 MB 的 Qwen 模型，随后可离线使用；没有 API Key 或订阅要求。模型准备期间可使用系统 Apple 本地识别，具体状态在设置显示。
- 语音板只有复制和语音状态两个常驻按钮。右侧按钮暂停/恢复收音；菜单栏点击展开菜单，单独控制语音板显隐。
- 连续文字可选择、编辑、复制；短暂停顿继续原段，约30秒静音后再次讲话另起自然段。面板的复制按钮取用完整自然段，包括滚动区域外的内容；系统选区复制仍可使用。档案按相同段落组织，支持搜索、星标、回听和重识别。这些段落细节对应1.1.0开发候选。
- 普通表达只需麦克风权限；记录、编辑、复制及回听不需要辅助功能权限，不需要快捷键，也不需要选择外部应用。跨应用插入及旧云端配置作为兼容功能保留，普通使用无需设置。
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
