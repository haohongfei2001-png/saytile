# Saytile

**自然开口，随时取用。**

Saytile 是 macOS 原生语音输入与表达工作台。开启后持续待命，自然讲话即可分段记录、识别中文，并独立保存原音。文字可以编辑、搜索、回听、重新识别、复制，或追加到明确选择的应用草稿。

V1 Release Candidate 已完成工程回归，真实讲话与个人环境验收仍明确保留，下载见 [Releases](https://github.com/haohongfei2001-png/saytile/releases)。要求 **Apple Silicon / macOS 26+**。源码继承 PR #1 的完整设计、原型和数据契约；历史原件保留在 `archive/`。

## 构建和运行

```sh
scripts/package-beta.sh
# 打开 dist/Saytile-1.0.0-rc.1-arm64.dmg 安装
```

同步盘可能在 App 目录附加影响签名的 Finder 元数据，请通过 DMG 安装至 Applications 后运行。

现有 Command Line Tools 即可构建，不要求安装完整 Xcode。App 使用系统框架和已固定提交的 WebRTC VAD，构建不下载语音模型。首次开启时准备 Apple 中文语言资源；识别失败仍保留原音。

```sh
scripts/test-native.sh
scripts/test-app-model.sh
python3 scripts/verify.py
scripts/package-beta.sh
```

原生测试和 AppModel 检查均用独立测试资料，不操作私人录音或外部草稿。`scripts/test-ax-fixture.py` 只在已有辅助功能权限下使用专用后台文本框。

## 使用

点击菜单栏或按 ⌥ 空格打开输入板。第一次点击开启收音后，后续讲话自动采集；关闭输入板继续待命，暂停随时可用。档案支持搜索全部文字版本、编辑草稿自动暂存、收藏、回听和重新识别。

复制无需辅助功能。跨应用插入需要本人允许辅助功能；目标应用、页面或光标改变会暂停自动输入。Saytile 不发送消息，不按新识别版本重复插入全文，不重试不确定投递。输入板只包含本次表达及明确带回的历史内容。

原音默认保留到手动删除；仅删除原音会保留文字及修改版本。10 GB 是提醒阈值，不是自动删除许可。资料位于 `~/Library/Application Support/Saytile`。

## 交付与验证

- [RC 验证与最终清单](docs/V1-RC-ACCEPTANCE.md)
- [安装说明](docs/V1-INSTALL.md)
- [实时开发状态](docs/V1-DEV-STATUS.md)
- [实际测试记录及限制](docs/V1-TEST-RESULTS.md)
- [最少用户授权与验收事项](docs/V1-USER-ACTIONS.md)
- [产品设计](docs/01-PRODUCT-AND-ROADMAP.md)、[架构](docs/02-V1-ARCHITECTURE.md)、[数据契约](docs/03-REBUILT-REVIEW-CONTRACTS.md)
- [原型](prototype/index.html)、[历史来源](docs/06-PROVENANCE.md)、[第三方许可](THIRD_PARTY_NOTICES.md)

个人包采用 ad-hoc 签名，尚未进行 Developer ID 公证。合成语音、后台 AX 测试、硬件缓冲统计、实际真人输入和整机功耗是不同验证层，详见测试记录。V2 轻声识别与 V3 个人词库/文字输入法不在本轮范围。
