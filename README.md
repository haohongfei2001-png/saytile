# Saytile

**本设计分支的原生预览**已实现无限连续时间轴。可并排安装，默认以 2 分钟空闲形成新组，并支持随时回看和一键复制。[签名预览、截图、窗口录制和验证报告](docs/V1-CONTINUOUS-TIMELINE.md)

> **最新产品增量决定（2026-11-09）：** [无限语音时间轴、一键复制、未来说话人模式、可选 ASR 及忠实原话](docs/PRODUCT-DECISIONS-2026-11-09.md)。这是后续产品目标，不是 no-api.10 已完成的能力；任何旧“双 ASR 同时运行”描述均已被 [单 ASR 权威架构](research/architecture/FINAL-ARCHITECTURE.md) 取代。


Apple Silicon，macOS 26 或以上。冻结 RC2 无 API 工程候选为 `1.0.0-rc.2-no-api.10`，采用每段一个 ASR 和 GPT-6 文本审校。[安装包与机器验收](docs/V1-NO-API-DELIVERY.md)。
<!-- frozen-machine-current:end -->

> **唯一批准的视觉设计原图**：[Saytile 原版设计全图](design/approved/Saytile-original-visual-reference-20261107.jpeg) · [原图与变更边界](design/approved/README.md)。应用外观必须以此图为唯一标准，只有用户指定的语音按钮交互与必要动效可以修改。原图已按附件原始字节入库，不能拿工程预览或近似色板替代。


**自然开口，随时取用。**

Saytile 是 macOS 原生语音输入与表达工作台。开启后持续待命，自然讲话即可分段记录、识别中文，并独立保存原音。文字可以编辑、搜索、回听、重新识别、复制，或追加到明确选择的应用草稿。

GitHub Releases 的稳定版本为 RC1，下载见 [Releases](https://github.com/haohongfei2001-png/saytile/releases)。本分支的 no-api.10 候选及证据见 [无 API 交付](docs/V1-NO-API-DELIVERY.md)；真实云端、讲话质量与个人环境验收仍明确保留。要求 **Apple Silicon / macOS 26+**。源码继承 PR #1 的完整设计、原型和数据契约；历史原件保留在 `archive/`。

## 最高质量中英文识别候选

当前契约是每段录音一个语言 ASR 专家、唯一 GPT-6 Astra 文本核心和单份忠实文字流；Apple 本地识别仅用于离线与故障接替。不得恢复并行 ASR、五模型默认链、润色或第二评审器。见 [最终架构](research/architecture/FINAL-ARCHITECTURE.md)。

本分支保留 PR #4 的可靠性修复、PR #5 的产品契约和 PR #6 的单核心引擎。没有 API Key 时可使用 Apple 本地中文识别；云端凭据在原生设置里填写，由一次明确授权的内置合成语音检查验证所选 ASR 的接收、GPT 的文字审校和定稿，全部通过后自动启用。无需修改JSON或终端联调；真实连接与准确率状态严格分开。参见 [安装与连接](docs/V1-INSTALL.md)。

## 构建和运行

```sh
scripts/package-beta.sh
# 输出文件名使用 packaging/VERSION；本分支为待云端验收的 RC2 候选
```

同步盘可能在 App 目录附加影响签名的 Finder 元数据，请通过 DMG 安装至 Applications 后运行。

现有 Command Line Tools 即可构建，不要求安装完整 Xcode。App 使用系统框架和已固定提交的 WebRTC VAD，构建不下载语音模型。首次开启时准备 Apple 中文语言资源；识别失败仍保留原音。

```sh
SAYTILE_SIM_FULL_SUITE=1 scripts/test-protocol-simulator.sh
scripts/test-app-model.sh
python3 scripts/verify.py
scripts/package-beta.sh
```

原生测试和 AppModel 检查均用独立测试资料，不操作私人录音或外部草稿。`scripts/test-ax-fixture.py` 只在已有辅助功能权限下使用专用后台文本框。

## 使用

点击菜单栏或按 ⌥ 空格打开输入板。第一次点击开启收音后，后续讲话自动采集；关闭输入板继续待命，暂停随时可用。档案支持搜索全部文字版本、编辑草稿自动暂存、收藏、回听和重新识别。

复制无需辅助功能。跨应用插入需要本人允许辅助功能；检测到目标应用、页面或光标变化时会暂停自动输入。并非所有网页都提供可区分的页面身份；完整前台浏览器插入及隐藏路由的支持边界见 RC 验证清单，不承诺泛网页兼容。Saytile 不发送消息，不按新识别版本重复插入全文，不重试不确定投递。输入板只包含本次表达及明确带回的历史内容。

原音默认保留到手动删除；仅删除原音会保留文字及修改版本。10 GB 是提醒阈值，不是自动删除许可。资料位于 `~/Library/Application Support/Saytile`。

## 交付与验证

- [当前 RC2 工程验收与限制](docs/V1-NO-API-DELIVERY.md)
- [RC1 验证清单（历史）](docs/V1-RC-ACCEPTANCE.md)
- [安装说明](docs/V1-INSTALL.md)
- [实时开发状态](docs/V1-DEV-STATUS.md)
- [实际测试记录及限制](docs/V1-TEST-RESULTS.md)
- [最少用户授权与验收事项](docs/V1-USER-ACTIONS.md)
- [产品设计](docs/01-PRODUCT-AND-ROADMAP.md)、[架构](docs/02-V1-ARCHITECTURE.md)、[数据契约](docs/03-REBUILT-REVIEW-CONTRACTS.md)
- [原型](prototype/index.html)、[历史来源](docs/06-PROVENANCE.md)、[第三方许可](THIRD_PARTY_NOTICES.md)

个人包采用 ad-hoc 签名，尚未进行 Developer ID 公证。合成语音、后台 AX 测试、硬件缓冲统计、实际真人输入和整机功耗是不同验证层，详见测试记录。V2 轻声识别与 V3 个人词库/文字输入法不在本轮范围。


## Current recognition architecture (2026-11-07)

Two equal ASR experts receive the same complete audio, and one GPT-6 Astra core continuously reviews their candidate evidence. The UI presents one transcript. GPT-6 Astra is text-only in the API; it does not directly hear audio. See [the final architecture](research/architecture/FINAL-ARCHITECTURE.md), [API capability decision](research/asr/DECISION.md), and [implementation status](research/architecture/PROJECT-STATUS.md).

## SingleTranscriptEngine 最新验收

双平等完整音频专家、一个GPT核心、唯一文字流、离线接替和安全局部修正的[早期引擎验证记录](evidence/single-transcript-final/README.md)。工程回归通过不等于真人云识别质量通过；生产RC1保持不变。

并发收口记录：[另一工程验收切片](evidence/single-transcript/DELIVERY.md)。最新统一回执以 [single-transcript-final](evidence/single-transcript-final/README.md) 为准，历史包与其真实来源SHA分别保留。

## 当前唯一批准的 V1 界面目标

Saytile V1 的唯一正式 UI 目标见 [唯一界面设计规范](docs/SAYTILE-V1-COMPACT-TRANSCRIPT-PANEL-DESIGN.md)。主面板无 Logo/字标和顶部操作栏；连续文字下方只有左侧复制与右侧语音胶囊。暂停（含首次未开）为播放三角，待命为圆点，真实讲话为波形；声音结束后回到待命，不等待后台识别定稿。编辑和其他操作仍可通过菜单及既有入口使用。此前冲突的品牌与界面探索均已舍弃；历史原型仅供追溯。
