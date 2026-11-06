# 内置连接检查：范围与预算

2026-11-07；工程证据，不是真实云端验收。唯一延续 PR #6。

正式设置中准备 Qwen、AssemblyAI、GPT-6 Astra 的 Keychain 凭据及各项处理授权。用户单独授权一次可能产生费用的检查后，使用正式 MultiRecognitionSession → SingleTranscriptEngine → Store 和正式网络客户端，发送相同的内置 PCM 给两个 ASR。GPT 只收候选文本；正常持续修正与 EOS 完整证据复核仍经过现有选择、数字/否定、代次和输入所有权校验。全套通过后自动应用云端配置；无凭据或部分失败仍可离线使用。

检查音频是 macOS 已安装 Tingting/Samantha 语音合成的新文本；没有录制环境声音：

- “连接检查。今天温度二十三度。”
- “Connection check. Please save this draft.”
- 16 kHz、单声道、PCM16LE、6.2720625 秒。
- SHA256 `5d29f5fc799a571b27d80bcf442004ba78a619c0d6e847258bb2b6b8b075387a`；包内读取强制核验。源资产随包分发，无运行时下载。

单次最多 90 秒、两条音频会话、6 次实际 GPT 请求（重连及 HTTP fallback 共用额度）、每次最多 4096 输出 Token。仅检查限制实时复核到一轮（重连后再 HTTP 回退最多占三次请求），为 EOS 留下额度；日常正常识别没有此限制。取消会关闭并等待本次会话，不能撤销服务商已处理的请求。无自动后台重试。没有真实密钥时，本轮没有任何收费调用。

费用是公开单价估算而不是账单保证。GPT-6 Astra 标准输出 $50/百万 Token，6×4096 的输出上限约 $1.23，另有输入/缓存费用。AssemblyAI 按整个连接持续时间计费；Qwen Message 按输入/输出 Token 计费，不能以音频秒数伪算。账户折扣、税费、额度及服务端计费以用户账户为准。

官方依据（本轮已核对）：
- https://developers.openai.com/api/docs/models/gpt-6-astra
- https://developers.openai.com/api/docs/guides/websocket-mode
- https://help.aliyun.com/en/model-studio/qwen-audio-3-1-asr-flash-message
- https://www.assemblyai.com/docs/faq/how-does-universal-streaming-session-based-pricing-work

账户/协议接受和完整转写是不同阶段。当前只存在模拟器与本地证据；模拟器报告明确 live=false，永远不能启用云端。真实报告仅确认合成语音的连接/融合/定稿，不能升级到 QUALITY_VERIFIED。配置身份、地域、Workspace、处理授权或凭据变化会撤销旧收据；退出与取消必须等待自己拥有的请求结束。不读取或上传历史音频、话题或用户草稿；报告只保留合成文本、安全错误类别和服务用量。
