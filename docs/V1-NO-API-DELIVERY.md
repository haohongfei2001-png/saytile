> **no-api.8 · 原稿校准候选**：最新用户上传的 1536×1024 JPEG 现有独立[来源与度量](V1-ORIGINAL-REFERENCE-FIDELITY.md)。上一版 no-api.7 已独立完成原生检查和 1,800.44 秒音频比对，但其卡片近似稿被否决，只保留为工程历史。新版本以原稿尺寸、正文、灰色双框复制图形和语音胶囊为准，将在新冻结版本执行验收；真实云端仍未连接。

# Saytile V1 RC2 · no-api.7 无密钥工程交付

**无密钥短项已通过，长跑结论待定 · LIVE_CONNECTION_PENDING**。[运行源码 `4b97bd89`](https://github.com/haohongfei2001-png/saytile/commit/4b97bd89b258fea29a0be61d4bd4c23cb5ab428c)，tree `4aac670d6edfcce0c12ed22fa3cd5c68e66061b9`。 适用于 Apple Silicon、macOS 26 或更新版本。RC1 继续作为稳定版本。个人候选采用 ad-hoc 签名，已验证挂载与解包 App 签名，尚未 Developer ID 公证。本检查点记录已校验的候选 DMG。公网下载回读结果在最终报告中单列。

[候选 DMG](../deliverables/no-api.7/Saytile-1.0.0-rc.2-no-api.7-arm64.dmg) · [SHA-256 清单](../deliverables/no-api.7/SHA256SUMS.txt) · [安装、备份与回退](V1-INSTALL.md) · [以后启用服务](V1-USER-ACTIONS.md) · [PR #6](https://github.com/haohongfei2001-png/saytile/pull/6)

DMG SHA-256 为 `0e2a2851d69687631fbbf4b8b5c2bd4fff750125cb0c798dcf67188f50c58f19`，解包 App 可执行文件为 `7f0dc84ecfd084f65d0700103648fa3be2f098d133a1873bfe5b20d3690c2b92`。本轮使用独立资料库，保留已安装 RC1。[包身份](../evidence/no-api7/final/package-identity.json)

## 本版可用范围

- 无 Key 可启动、持续保存原音。机器已准备 Apple 中文资源时可识别、搜索、回听、编辑与复制。仅删除原音时保留文字及修改版本。识别、音频保存与安全投递分别记录。
- 输入板底部只有复制与语音胶囊。未开启和暂停时显示右向三角，待命显示圆点，有效讲话显示随音量变化的五根圆头竖条。VAD 结束即回待命，上一段定稿仍能写回原段。正文与复制按钮的上下文菜单保留编辑、档案、回到最新与明确绑定。
- 此版恢复面板局部紫蓝渐变、圆角与间距。正式包空板三处 sRGB 从旧版的 (250,250,253) 变为 (225,223,250)、(223,224,251)、(219,224,250)。边角透明，三个内部 PNG 取样点均已合成为不透明。真实壁纸透射、系统实屏动效和用户视觉判断未验证。[实际截图与数据](../evidence/no-api7/final/ui/REVIEW.md)
- 当前正式契约为 Qwen Audio 3.1 Message、AssemblyAI Universal 3.6 Pro 平等处理整段音频，唯一 GPT-6 Astra 接收候选文字以融合和定稿。首次设置支持 Keychain、按服务授权与内置合成语音检查。在线收音、融合和定稿在真实账户上的运行状态仍待验证。[云端证据边界](../evidence/no-api7/final/cloud-quality-boundary.json)

## 同一运行源码的实际验证

| 项目 | 实际结果 |
|---|---|
| 原生套件与协议 | 本机 Swift 392 个测试函数 / 48 套件 / 512 个展开场景，AppModel 104 项。 包含协议 12 个测试函数、52 个场景，其中 50 个经正式 URLSession 与 localhost HTTP/WS 对端交互，协议违例为零。以上计数存在包含关系。[原始记录](../evidence/no-api7/final/protocol/) |
| 首次连接和命令入口 | 隔离账户注入覆盖成功、失败、取消和撤权。命令边界 17+7 项。首次向导上的通过状态为 TEST_ONLY，尚无真实账户收据。[控制器与设置](../evidence/no-api7/final/input/app-model-dom.md) |
| 输入安全 | headless DOM 20 项，原生 AX 9 项，目标在 setter 后变化 5 项，范围修正 9 种。WKWebView 上下文 6 项、能力拒绝 2 项，发送零次。其后台 AX setter 确认收到请求，DOM 未变化，投递保留未确认且不重放。[原生输入](../evidence/no-api7/final/input/NATIVE-INPUT.md) · [范围修正](../evidence/no-api7/final/owned-range/) |
| 正式包原生 UI | 控件模式 37 图、45 次 AXPress、10 次菜单选择、11 次双控件检查及 6 次字段编辑（含 3 个安全字段）。纯渲染 27 图。两种模式各 71 个独立的中性图形参数采样。采样无法测量显示帧率、真实中断时序或新材质。[原生界面](../evidence/no-api7/final/ui/REVIEW.md) |
| Apple 中文合成识别 | 准备系统语言资源后完成 8/8 段，共 48.703 秒，逐条标准化 CER 为 0–26.32%。首显中位 1.199 秒，结束到定稿中位 0.051 秒。四处遗漏涉及 Mac、保存原音、充电器、修改开始时间。[原文、输出与口径](../evidence/no-api7/final/apple/) |
| 保存、恢复和规模 | VAD 首段保存 49,920 帧，在两个受控专家等待 final 时下一段已被接收，旧结果写回原段。12 项存储进程、异常、迁移、备份及恢复验证通过。100,000 条记录和 300,000 个版本下，部分写入 p95 0.165 ms，搜索 100 个结果耗时 133.163 ms。[本机记录](../evidence/no-api7/local/) |
| 安装、启动和空闲 | 已发布 RC1 到本包的 8 项安装升级检查，另有 2 项卸载重装检查。启动检查使用独立资料库并观察前台，未激活用户窗口。实际 App 空闲 300.036 秒，暖态 RSS 66,272–79,072 KiB。整机电耗与长期真人环境未测。[安装与升级](../evidence/no-api7/final/install-upgrade.json) · [未激活启动](../evidence/no-api7/final/startup-focus.log) · [空闲](../evidence/no-api7/final/app-idle.json) |

截至本检查点，30 分钟完整采集与独立逐帧比较尚无终态结论。本版的短项和独立 PCM 参考已经完成。[本版长期验证](../evidence/no-api7/local/)

冻结源码的[设计 CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42333550200)通过，[原生 CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42333550192)完成 Swift 和协议测试后在 AppModel 阶段取消，其后构建与 UI 跳过。仅改文档的 `54b4c40f` 对应的[原生 CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42333775516)和[设计 CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42333775472)均通过。其运行输入与冻结源码相同，完整 Git tree 不同。[CI 身份比较](../evidence/no-api7/final/protocol/docs-successor-ci/comparison.json)

## 尚待验证

真实云端请求为零。真人中文 CER、英文 WER、混合 MER，双专家加 AI 相对最强单模型的增益、适用场景及新增稳定确认延迟均未知。当前未进入集中真人验收。 云端故障、真实模型访问权限、音频上传与费用授权须在一次受控实连中验证。禁止用离线合成 CER 或最终文字更通顺推算云端改善。[各阶段质量状态](../evidence/no-api7/final/cloud-quality-boundary.json)

真实麦克风、物理设备拔插、锁屏/睡眠、真实多屏组合、任意第三方前台编辑器及长时间真人使用仍有未覆盖项。图像仅证明工程包的实际绘制与操作。仓库记录了指定参考图的身份和后续截图，但未取得原始 PNG 字节作逐像素比对。[参考来源](../evidence/no-api7/final/reference-source.json) · [独立审查](../evidence/no-api7/final/INDEPENDENT-REVIEW.md)

[no-api.6 的归档交付记录](https://github.com/haohongfei2001-png/saytile/blob/98ee61ad16ab9a5d7376846c70a89654667ddca7/docs/V1-NO-API-DELIVERY.md)与[原有安装包](../deliverables/no-api.6/)保留。 [旧 no-api.5 基线](../evidence/no-api-product/final-no-api5-r2/BASELINE.md)。这些记录仅供追溯。
