# Saytile

最新独立开发候选为 **0.21（557）**，整合 PR49/50，尚未公开发布或替换安装。[准确率、真实原生验收和发布裁决](docs/delivery/beta-021/STATUS.md)。

本机个人内测为 **Saytile 0.20（533）**，支持 Apple Silicon、macOS 26 及以上版本。应用名称为 Saytile，版本与构建号在「关于」中显示。官网公开 Beta 为 0.18（492）。[本机版本与回退](docs/delivery/saytile-next-release/RELEASE.md) · [各项验收状态](docs/delivery/saytile-next-release/STATUS.md)

设置「外观」新增已批准的黑色品牌选项，紫色继续作为默认。见 [图稿来源及范围](docs/BLACK-BRAND-OPTION2.md)。

拖左、右边缘调宽度，拖上、下边缘调高度，可以停在长而窄的尺寸。收音键位于右下角。点击菜单栏图标打开菜单，选择当前可用的「收起语音板」或「展开语音板」。要把窄板调回原来的阅读尺寸，在窄板语音键上打开快捷菜单，选择「恢复阅读尺寸」。在「语音档案与设置…」中可按日期回听讲话、编辑文字和收藏记录。

## 录音与识别

首次点语音板右下角启用收音。想长期待命时，在「麦克风」勾选「重新打开时恢复待命」。主动暂停或退出后，下次启动尊重这一选择。自然停顿形成的段落也用于档案和一键复制；选中文字时优先复制选区。

每段使用一个识别引擎。中文在已安装并通过校验时优先使用本地 Qwen3-ASR 0.6B。未就绪时按可用资源回退，模型选择在下一段生效。原音在本机独立保存。云端识别、GPT 文字复核与直接输入各自需要用户明确启用。[同机中文原速测量](docs/delivery/saytile-next-release/QUALITY.md) · [单 ASR 架构](research/architecture/FINAL-ARCHITECTURE.md)

主板保留连续可编辑文字、复制和收音键。「语音板外观」可以选择面板与按钮颜色、边框、字号、默认大小和透明度。透明度提供通透、柔雾、浓雾和不透明四档。[批准的原始视觉](design/approved/README.md) · [自然语音时间轴决定](docs/PRODUCT-DECISIONS-2026-11-09.md)

## 构建和运行

```sh
SAYTILE_MANDARIN_CANDIDATE=1 SAYTILE_SIGN_IDENTITY="<Developer ID 身份的 SHA-1>" scripts/package-beta.sh
# 内测镜像文件名包含版本、构建号和架构，镜像内只有 Saytile.app。
```

同步盘可能在 App 目录附加影响签名的 Finder 元数据，请通过 DMG 安装至 Applications 后运行。

App 使用系统框架和固定版本的 WebRTC VAD。第三方模型权重按需下载。本次完整 Swift 与 iOS Simulator 测试使用具备完整 Xcode 的 macOS CI。

```sh
SAYTILE_SIM_FULL_SUITE=1 scripts/test-protocol-simulator.sh
scripts/test-app-model.sh
python3 scripts/verify.py
```

原生测试和 AppModel 检查均用独立测试资料，不操作私人录音或外部草稿。`scripts/test-ax-fixture.py` 只在已有辅助功能权限下使用专用后台文本框。

## 档案、升级和恢复

菜单中的「语音档案与设置…」提供搜索、编辑、星标、回听和重新识别。仅删除原音会保留文字、历史版本和草稿。窗口切换使外部输入绑定失效；应用不会自动发送或补发未确认的投递。复制无需辅助功能权限。

现有中文内测身份沿用 `~/Library/Application Support/Saytile Mandarin Candidate`。历史 0.12 的档案位于独立目录。日常升级替换原处应用即可。需要合并旧档案时，工具读取两份明确指定的副本，并将验证后的结果写入一个新目录。[安装和数据恢复](docs/INTERNAL-INSTALL.md) · [命令与账户条件](docs/delivery/saytile-next-release/HANDOFF.md)

## 工程和历史记录

- [交付记录、签名和验收证据](docs/delivery/saytile-next-release/RELEASE.md)
- [已知问题与修复](docs/delivery/saytile-next-release/ISSUES.md)
- [真实服务、原生窗口与离线测试的范围](docs/delivery/saytile-next-release/ACCEPTANCE.md)
- [冻结 RC2 的无 API 记录](docs/V1-NO-API-DELIVERY.md) · [RC1 验收](docs/V1-RC-ACCEPTANCE.md)
- [早期文字引擎记录](evidence/single-transcript-final/README.md) · [数据契约](docs/03-REBUILT-REVIEW-CONTRACTS.md) · [历史资料来源](docs/06-PROVENANCE.md) · [第三方许可](THIRD_PARTY_NOTICES.md)
