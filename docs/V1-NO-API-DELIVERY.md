# Saytile V1 RC2 · 无 API 工程交付

正式开发在 [PR #6](https://github.com/haohongfei2001-png/saytile/pull/6)。当前稳定发布仍为 RC1。本候选为 **1.0.0-rc.2-no-api.6**，适用于 Apple Silicon、macOS 26 或更新版本。它没有替换已安装的 RC1，也没有修改生产资料库。

**候选来源**：[运行源码 `4551433`](https://github.com/haohongfei2001-png/saytile/commit/455143310222c2c03c4a4888e5df5552c3af4131)，tree `87015ba6c1cb2b38c5a868a2fed1b86b9eaac683`。[DMG 与 SHA-256](../deliverables/no-api.6/) · [安装、备份与回退](V1-INSTALL.md) · [以后启用服务的设置步骤](V1-USER-ACTIONS.md)。DMG 挂载原件与解包 App 均通过严格签名验证；为 ad-hoc 签名，未 Developer ID 公证。

## 用户现在可使用什么

- 无 Key 可启动、保存原音，并在 Apple 中文资源就绪的 Mac 上识别。原音、历史文字、用户编辑稿和输入投递状态分别保存；识别失败可以恢复，删除原音不会顺带删除文字。
- 输入板底部只有复制和语音按钮。播放三角表示暂停，圆点表示待命，五根圆头小竖条跟随当前讲话的音量。VAD 判定句尾就回到待命，上一段定稿继续写回原段。选择或阅读旧文字时不会被后到的文字挤走。正文与复制按钮右键菜单均可到达编辑、回到最新、档案、设置和明确绑定等操作。
- 设置向导在本人提供三项凭据、Qwen 地域/Workspace 和相应授权后，自动运行有边界的真实连接检查；只有两个语音服务及 GPT 文本融合、EOS 定稿全部成功，才开启完整云端路径。失败保留本机功能与已存内容。实际云请求本轮为 **零**。

## 这个 SHA 实际验证了什么

| 层级 | 观察结果 |
|---|---|
| 完整 Swift / 实际 loopback 协议 | 392 个函数、48 套件，含 12 个协议测试函数、52 种协议场景；其中 50 次使用正式 URLSession 客户端和 localhost HTTP/WS 对端，零协议违例。包含同 PCM 双路、持续文字修正、EOS、重连、结构化错误与同模型 HTTP 回退。[原始记录](../evidence/bottom-controls/final/protocol/) |
| 产品控制器 / 密钥 / 首次向导 | 104 项 AppModel 检查通过；隔离真实 Keychain 测试与注入账户/合成向导测试分别记录。命令入口边界 17+7 项。向导的测试成功状态不等于真实账户已连接。 |
| 实际 Mac 文字输入 | headless DOM 20，隔离原生 AX 9，目标在 setter 后变化 5，原生所有权 9；WKWebView 上下文 6、能力拒绝 2、零发送。WK setter 返回接受但 DOM 不变，实际投递仍为 **未确认**，不得重放。[输入记录](../evidence/bottom-controls/final/input/) |
| 实际 DMG 内 App 原生界面 | 控件模式 37 张原生图、45 次 AXPress、10 次上下文菜单选择、11 次双控件几何/状态核查、6 次字段编辑（含 3 个安全字段）；另有 27 张纯渲染图。逐个检查了选区/全文复制、回到最新、档案编辑、向导与暂停恢复。两种模式各自另外渲染 71 帧生产语音图形采样；不是 71 张实际播放时序截图。[控件操作](../evidence/bottom-controls/final/ui/) · [纯渲染](../evidence/bottom-controls/final/ui-render-only/) |
| Apple 本机中文识别 | 系统初报资源未安装；产品原有准备流程一次后就绪，未移除其他语言。8/8 合成样本识别完成，48.703 秒，逐样本 CER 0–0.2632；首显中位 1.202 秒，结束至定稿中位 0.054 秒。四处关键遗漏：Mac、保存原音、充电器、修改开始时间。[逐条输出与时间](../evidence/bottom-controls/final/apple/) |
| 原生采集、保存与恢复 | 真实 WebRTC VAD 与 ring：第一段 49,920 帧 WAV 已保存；两个受控专家都在等待 final 时，第二段已经开口并得到独立文字；旧定稿只写回第一段，ring 无丢帧。12 项真实进程/存储检查通过，包含强杀、写失败、迁移以及完整备份回退。 |
| 安装、启动与后台运行 | 从已发布 RC1 DMG 到实际候选的 8 项检查、卸载重装 2 项、连续重启/单实例锁均通过。合成数据库行、草稿、原音和未确认投递受到保护。340×240 pt 面板启动未抢前台；展开小入口不启动收音。[安装记录](../evidence/bottom-controls/final/install-upgrade.json) |
| 性能边界 | 10 万条记录、30 万版本：阶段写入 p95 0.152 ms、搜索 100 匹配 121.835 ms。实际 App 无采集空闲 300.02 秒，暖态 RSS 63,520–79,280 KiB；该进程 CPU 0.29 user + 0.14 sys 秒。不是电池、整机能耗或 72 小时结果。 |
| CI | 同源码的 [macOS 原生](https://github.com/haohongfei2001-png/saytile/actions/runs/42331341272)及[设计契约](https://github.com/haohongfei2001-png/saytile/actions/runs/42331341221)均成功。CI 的纯渲染与本机实际 AX 操作分开，不叠加计数。 |

长跑：使用提交的合成 AIFF，按真实时钟馈入生产 ring/VAD/保存链；结束后将每一帧与独立转换参考比较。运行中的累计帧数不等于通过。见[本轮长期运行证据](../evidence/bottom-controls/local/)。

## 哪些结论不能从这些结果推出

**云端状态为 `LIVE_CONNECTION_PENDING`。** Qwen Audio 3.1 Message、AssemblyAI Universal 3.6 Pro 平等接收同一音频，唯一 GPT-6 Astra 接收文字候选，不听原音；Soniox 为可选、默认不启用。没有真实账户授权、没有付费调用、没有用私人或真人对话上传验证。与最强单模型相比的准确率增益、准确场景和额外确认延迟均 **未知**，不能写为 0，也不能由协议模拟或 Apple 的合成 CER 推算。未授予 `LIVE_PROTOCOL_VERIFIED`、`LIVE_TRANSCRIPTION_VERIFIED`、`QUALITY_VERIFIED` 或 `PRODUCTION_READY`。

隔离输入不是任意前台编辑器兼容认证，真实麦克风权限、物理设备拔插、睡眠/唤醒、多显示器实际组合、真人长用及公证均有边界。原图《Saytile语音输入工作台概念界面.png》在 GitHub 有[正式设计来源说明](../design/approved/README.md)和[后续已核布局规范](SAYTILE-V1-COMPACT-TRANSCRIPT-PANEL-DESIGN.md)；现有 PNG 实机图用于比对布局和状态，不能称为取得原始图像字节、从批准原图采色或用户已接受视觉。复制成功沿用简短提示，直接输入模式保留目标提示。[独立审查](../evidence/bottom-controls/final/INDEPENDENT-REVIEW.md)

上方按钮 no-api.5 的[原始测试、旧 DMG 及完整波形](../evidence/no-api-product/final-no-api5-r2/BASELINE.md)和此前 no-api.4 [冻结记录](../evidence/no-api-product/final-no-api4-r2/delivery-manifest.json)仅用于溯源，不用于给当前版本计数。真实连接和真人验收的最少后续事项见[验收条件](V1-RC2-FINAL-ACCEPTANCE.md)；当前不要求用户参与。
