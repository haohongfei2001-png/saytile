# Saytile RC2 · 单 ASR + GPT-6 · 无 API 封版

Apple Silicon，macOS 26 及以上。产品源码 `5639058e6b178027861b18cc0521387487c919d5`。[PR #10](https://github.com/haohongfei2001-png/saytile/pull/10) 保存冻结包和验收记录。源码冻结后仅更新验收工具或证据。

[下载唯一工程候选 DMG](https://raw.githubusercontent.com/haohongfei2001-png/saytile/319041e6d942122b0a42bfa54fcef5a1eb045942/deliverables/no-api.10/Saytile-1.0.0-rc.2-no-api.10-arm64.dmg) · [SHA-256](../deliverables/no-api.10/SHA256SUMS.txt) · [逐项机器收据](../evidence/no-api10/final/machine.json) · [构建日志](../evidence/no-api10/final/app/package.log)

| 项目 | 最终记录 |
| --- | --- |
| 版本 | `1.0.0-rc.2-no-api.10` |
| 镜像 | 2,617,473 字节，公开下载回读一致 |
| SHA-256 | `62e0054ea9372d149c353ddc0f44f5e341b3a7d68d5b78c1f0c5a9d656e5154f` |
| 核心接入准备 | `READY_FOR_AUTHORIZED_API_ACCEPTANCE` |
| 完整无 API 实机验收 | BLOCKED |
| 标准公网分发 | BLOCKED；App 与镜像的 Developer ID 签名有效，Gatekeeper 拒绝未公证下载 |
| 真实 ASR、GPT-6 和人声质量 | NOT_RUN |

## 已实际测得

- 完整 Xcode 26.6 (17F113) 无过滤运行 48 组、401 项 Swift Testing，通过 401，失败 0，跳过 0。另有 104 项控制器检查和 52 个真实 localhost 协议案例。模型为测试端点。[完整 Xcode 收据](../evidence/no-api10/final/tests/xcode.json)
- 独占真实前台的 WKWebView、NSTextView、TextEdit 验证首次输入、长短 UTF-16 修正、用户编辑和前后文字保护、焦点或窗口变化、不确定投递及重启拒绝重放。冷启动附加运行出现过首次写入前拒绝绑定；保留了原始失败和复测。[前台原始记录](../evidence/no-api10/final/input/)
- 独立 Mac 从交付镜像提取签名 App。实际执行 41 次 AXPress、10 次菜单选择、5 次字段编辑，覆盖恰好两个安全凭据字段、15 组原生控件。连接后端为隔离替身。Keychain 在单独的真实系统钥匙串测试中使用随机服务名和合成凭据验证。[签名包控件](../evidence/no-api10/final/ui/) · [独立安装收据](../evidence/no-api10/final/app/signed-installation.json)
- 签名 App 实际收到了物理设备回调。两个物理麦克风的切换为 **PASS**。内置输入 → Bluetooth 输入 → 内置输入，三段均收到帧，系统默认输入和输出保持原设置。另在两种 Core Audio 聚合路由上验证采集中移除、拒绝旧设备和恢复。设备探针仅计帧，无 WAV 和录音记录。[物理路由](../evidence/no-api10/final/hardware/)
- 运行中的专用虚拟 Mac 实际断网后，已开始记录合成讲话；恢复网络后验证保留原音 25,259 帧。受控睡眠通知中封存第一段、唤醒后产生新段，手动暂停保持。12 项独立进程测试覆盖低磁盘空间、SIGKILL、SQLite/WAL 及原音恢复。[生命周期](../evidence/no-api10/final/lifecycle/) · [存储](../evidence/no-api10/final/store/recovery.json)
- 持续按真实时间重放两句已确认来源的合成语音 2.00 小时，经正式采集、VAD 与 Apple 本机识别，定稿 80/80、含实时文本 80/80、有效原音 80/80，丢帧计数 0、采集工作器错误 0。签名 App 实际暂停常驻 90.0 分钟，隔离数据库和录音目录已检查。[连续语音](../evidence/no-api10/final/speech/result.json) · [签名 App 常驻](../evidence/no-api10/final/signed-idle/result.json)
- 独立连续讲话负载使用相同的采集模块，在真实时间内无间隔循环合成短句 30 分钟。ASR 关闭，以验证长期音频落盘和待处理队列；共保存 1800.00 秒，179 个原音文件，逐项核对 WAV 头和 SQLite 帧数。[持续讲话与原音轮换](../evidence/no-api10/final/continuous/result.json)
- 活跃进程平均 CPU 1.53%，采样 RSS 峰值 38.42 MiB；暂停 App 为 0.20% 和 75.27 MiB。活跃数据来自链接正式模块的采集进程，暂停数据来自交付的 App；未计独立系统识别进程和整机电耗。90 分钟 RSS/CPU 的 91 个样本完整。其物理内存与能耗附属文件被重启后的测试启动器截断；另以同一签名二进制独立复测 10 分钟，结果单列。[资源计数](../evidence/no-api10/final/resources.json)
- RC1 升级与回退 8 项通过；no-api.9.1 升级时 26 张表及原音保持一致。使用独立安装和合成数据。[RC1 升级](../evidence/no-api10/final/app/upgrade.json) · [no-api.9.1 升级](../evidence/no-api10/final/app/upgrade-9.1.json)

## 剩余边界

- **FAIL**　带下载隔离属性的 DMG 及 App 被 Gatekeeper 拒绝，原因为 Unnotarized Developer ID。已验证 Apple Developer ID、Hardened Runtime、音频输入 entitlement 和可信时间戳。公证及装订等待授权的 Apple notarytool 身份。[签名收据](../evidence/no-api10/final/app/signing.json) · [Gatekeeper](../evidence/no-api10/final/app/signed-installation.json)
- **BLOCKED**　真实内核睡眠以本次[被动观察](../evidence/no-api10/final/lifecycle/passive.json)和[托管机的系统调用](../evidence/no-api10/final/lifecycle/power.json)为准。独占虚拟机拒绝实际睡眠。共享 Mac 的可靠定时唤醒权限不可用。实际拔除正在录音的物理附件，以及同一 App 的系统麦克风授权撤销后重新授予，仍缺少受控条件。
- **NOT_RUN**　真实语音服务、GPT-6、真人 CER/WER/MER 和确认延迟均待授权。中文 Qwen、英文 AssemblyAI、中英混说 Soniox 均为路由候选。Auto 没有可信语言记录时走本机；录音中锁定一个 ASR。没有实测模型排名。

[API 接入与单次调用范围](V1-RC2-CONNECTION-SETUP.md) · [安装、升级及回退](V1-INSTALL.md) · [授权事项](V1-USER-ACTIONS.md)
