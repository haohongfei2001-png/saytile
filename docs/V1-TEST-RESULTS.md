# V1 验证结果 · no-api.9

冻结 no-api.9 的补充实机验收见[机器报告](../evidence/no-api9/machine-freeze/README.md)。本机物理输入计数和隔离升级已执行，72 小时观察进行中。当前无需用户录音、操作窗口或提供密钥。

**`NO_API_ENGINEERING_READY` · `LIVE_CONNECTION_PENDING`**。[运行源码 `dc26fe3c`](https://github.com/haohongfei2001-png/saytile/commit/dc26fe3c59ba55994d29e99ada8d2f0b49ad9886)，源树 `f138f6733a642a2e53da22b3647aaf5744cb308b`。 [候选 DMG](https://raw.githubusercontent.com/haohongfei2001-png/saytile/0aa51620c63612246395d8f2a83e1eb96c9e94c4/deliverables/no-api.9/Saytile-1.0.0-rc.2-no-api.9-arm64.dmg) · [校验和](../deliverables/no-api.9/SHA256SUMS.txt) · [最终证据清单](../evidence/no-api9/final/delivery-manifest.json) · [公开下载回读](../evidence/no-api9/final/public-download.json)。

393 个原生函数、48 套件、513 个展开场景；AppModel 104 项。50 个 localhost 网络案例包含在这些检查内，未作真实云调用。 成品输入板 45 次 AXPress、10 次菜单选择及 11 次双控件几何测量。Apple 合成语音 8/8；Gatekeeper 拒绝普通公开分发。合成信号按实时时钟运行 1,800.41 秒；60 段、179 个 WAV，28,800,000 帧。和独立转换参考逐字节一致，差异 0，ring 丢帧 0，上传授权 0，23/23 项通过。采集进程 RSS 15,632–17,568 KiB，进程 CPU 时间占单核墙钟 1.55%；此项关闭麦克风和 ASR。

[完整交付、实测与边界](V1-NO-API-DELIVERY.md) · [上一阶段记录](https://github.com/haohongfei2001-png/saytile/blob/dc26fe3c59ba55994d29e99ada8d2f0b49ad9886/docs/V1-TEST-RESULTS.md)。未取得真实账户与上传授权，真实服务调用为零。双专家加 GPT 相比最强单模型的准确率改善、改善场景及附加确认延迟均未知；真实协议、真实转写、质量及生产发行状态均未通过。

补充实机验收复现了一个 P2 状态显示问题。已暂停的 AudioController 在受控睡眠、唤醒通知后仍显示“Mac 已睡眠”，录音数为零。未改动冻结源码。[实测](../evidence/no-api9/machine-freeze/paused-wake.json)
