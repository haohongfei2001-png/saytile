# 双平等专家 + GPT-6：正式识别决策

更新：2026-11-07。权威契约见 [FINAL-ARCHITECTURE](../architecture/FINAL-ARCHITECTURE.md)。本次已确定架构，没有伪造模型质量冠军。

| 职责 | 工程起始候选 | 证据与限制 |
|---|---|---|
| 中文专家 | `qwen-audio-3.1-asr-flash-message` | 官方 WebSocket、partial 与多语言能力；不启用 disfluency removal；Saytile 云端质量未测 |
| 英文专家 | `universal-3-6-pro` | 官方实时服务；完整音频，不限制仅英文；Saytile 云端质量未测 |
| 唯一融合核心 | `gpt-6-astra` / Responses | 文本/结构化/流式；Audio NOT SUPPORTED；不得冒称听过音频 |
| 挑战者 | Soniox `stt-rt-v6`、Meta Muse、SeedASR 等 | 不是主模型；与 Qwen3-ASR、Scribe 实时/文件能力分开对照；没有实测收益不默认增加 |

默认两个 ASR 平等接收完整同一音频。GPT 持续合并证据，收尾必做最终评审。仅忠实转写，用户只看一份稿。不存在多个 LLM 投票、默认 Gemini/Scribe 复听链、润色或语言选择 UI。

A 中文+GPT；B 英文+GPT；C 双专家+GPT；D Soniox+GPT；E 双专家+Soniox+GPT；F GPT 原生音频。F 因 Astra 不支持音频不可执行。A-E 用既有冻结 24 条相同真人语音，不改 ID/参考/音频；相近再扩 112 条。已有336条 Apple/本地Qwen是历史结果，不替代任何一项云实验。

## 本轮事实

Mac metadata-only 查询：Saytile 专用 Keychain 匹配 0，生产云配置不存在、cloud_enabled=false；未读取秘密、未弹授权提示、0 上传、0 付费测试。当前缺少本产品可用服务配置及授权，故 A-E NOT_RUN；不能宣布专家最终胜者。此结论不等于用户在其他工具中没有 API Key。

精确官方能力和来源见最终架构；接口可用性/厂商评测不等于真实产品准确率。GPT 首显与结束延迟尚需真实 API 测量，280ms 仅为合并窗口。
