# 用户事项 · no-api.9

冻结 no-api.9 的补充实机验收见[机器报告](../evidence/no-api9/machine-freeze/README.md)。本机物理输入计数和隔离升级已执行，72 小时观察进行中。当前无需用户录音、操作窗口或提供密钥。

**`NO_API_ENGINEERING_READY` · `LIVE_CONNECTION_PENDING`**。[运行源码 `dc26fe3c`](https://github.com/haohongfei2001-png/saytile/commit/dc26fe3c59ba55994d29e99ada8d2f0b49ad9886)，源树 `f138f6733a642a2e53da22b3647aaf5744cb308b`。 [候选 DMG](https://raw.githubusercontent.com/haohongfei2001-png/saytile/0aa51620c63612246395d8f2a83e1eb96c9e94c4/deliverables/no-api.9/Saytile-1.0.0-rc.2-no-api.9-arm64.dmg) · [校验和](../deliverables/no-api.9/SHA256SUMS.txt) · [最终证据清单](../evidence/no-api9/final/delivery-manifest.json) · [公开下载回读](../evidence/no-api9/final/public-download.json)。

目前无需安装、录音、点击测试、提供日志或替换 RC1。

以后选择启用云端时，只在“设置 → AI 识别 → 连接识别服务”输入 Qwen Key／地域／Workspace、AssemblyAI Key、具备 GPT-6 Astra 权限的 OpenAI Key，逐项允许对应数据处理，再确认内置合成语音检查和费用。不要把密钥发给开发人员或粘贴到 GitHub。检查成功才启用；本机功能不依赖云服务。

正式使用麦克风收音才需要麦克风许可；跨应用连续输入才需要辅助功能许可，复制不需要。Apple 中文资源可在原生设置中准备。普通公开发行还须由发行方完成 Developer ID 签名、公证，不需要用户放宽安全策略。

[完整交付、实测与边界](V1-NO-API-DELIVERY.md) · [上一阶段记录](https://github.com/haohongfei2001-png/saytile/blob/dc26fe3c59ba55994d29e99ada8d2f0b49ad9886/docs/V1-USER-ACTIONS.md)。未取得真实账户与上传授权，真实服务调用为零。双专家加 GPT 相比最强单模型的准确率改善、改善场景及附加确认延迟均未知；真实协议、真实转写、质量及生产发行状态均未通过。
