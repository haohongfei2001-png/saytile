> **no-api.9 · 中性透光材质**。唯一视觉依据是[已入库的完整原图](../design/approved/Saytile-original-visual-reference-20261107.jpeg)；原图蓝紫色来自卡片后方，面板及按钮本身为中性白色玻璃。单独给安装包版本，保留 no-api.8 固定色彩基准。正在准备本版的实际窗口合成和整合源码验证，真实云端仍未接通。

# 用户事项 · no-api.8

**无密钥短项已通过；本版 30 分钟长跑待定 · `LIVE_CONNECTION_PENDING`**。[运行源码 `69b90939`](https://github.com/haohongfei2001-png/saytile/commit/69b90939fd688b35448f976950e96db0ce5b602a)，源树 `06f1ac6982591bce64c98bd93e26eb0ccba0cfd8`。 [候选 DMG](../deliverables/no-api.8/Saytile-1.0.0-rc.2-no-api.8-arm64.dmg) · [校验和](../deliverables/no-api.8/SHA256SUMS.txt)。

目前无需安装、录音、点击测试、提供日志或替换 RC1。

以后选择启用云端时，只在“设置 → AI 识别 → 连接识别服务”输入 Qwen Key／地域／Workspace、AssemblyAI Key、具备 GPT-6 Astra 权限的 OpenAI Key，逐项允许对应数据处理，再确认内置合成语音检查和费用。不要把密钥发给开发人员或粘贴到 GitHub。检查成功才启用；本机功能不依赖云服务。

正式使用麦克风收音才需要麦克风许可；跨应用连续输入才需要辅助功能许可，复制不需要。Apple 中文资源可在原生设置中准备。普通公开发行还须由发行方完成 Developer ID 签名、公证，不需要用户放宽安全策略。

[完整交付、实测与边界](V1-NO-API-DELIVERY.md) · [上一阶段记录](https://github.com/haohongfei2001-png/saytile/blob/69b90939fd688b35448f976950e96db0ce5b602a/docs/V1-USER-ACTIONS.md)。未取得真实账户与上传授权，真实服务调用为零。双专家加 GPT 相比最强单模型的准确率改善、改善场景及附加确认延迟均未知；不授予 LIVE_PROTOCOL_VERIFIED、LIVE_TRANSCRIPTION_VERIFIED、QUALITY_VERIFIED 或 PRODUCTION_READY。
