# Saytile V1：One ASR Expert + One GPT-6 AI Core

更新：2026-11-07。**本文件正式取代此前“双 ASR 同时运行”架构。**历史双专家记录保留作审计证据，不再是生产实现目标。

## 唯一生产数据流

```text
CaptureWorker → PCMJournal → LanguageProfile / ASR Model Registry
             → one selected ASR Provider → ASR Candidate
             → one GPT-6 Astra text review core
             → SingleTranscriptEngine → one faithful transcript
             → ownership-checked external insertion

Apple SpeechAnalyzer = offline / network-failure fallback, never a parallel cloud expert
```

每个 recordingID/audioEpoch 只能启动一个云端 ASR。一个录音从首帧到 EOS 固定同一 provider/model；配置变化仅影响下一录音。禁止并行云 ASR、按句/Token 拆音频或在录音中途切换供应商。GPT 只处理 ASR 候选、上下文和可验证的替代证据，不支持原生音频输入，不得声称听过原音。

## LanguageProfile 与 Registry

用户语言偏好只有 Auto、中文、English、中英混说。显式偏好优先；Auto 使用近期 ASR 语言观察与 macOS locale 先验。近期中英使用均明显时选混说模型；语言无法可靠判断且没有已验证的多语言模型时，使用 Apple 本地识别/保留原音，不并发启动多个云模型。当前候选映射：中文 Qwen Audio 3.1 Message、英文 AssemblyAI Universal-3.6 Pro、中英混说 Soniox STT v6。它们不是质量冠军，须由冻结 24 条真实对照确定。

录音启动时将选中的 provider/model/configurationID 固定到该 generation；语言记录只用于下一段。配置及 Keychain UUID 保留，不静默替换 Key、模型或授权。未连接某语言服务时不得借用另一语言模型冒充适配；回退 Apple 或明确不可用。

## GPT-6 AI 核心

唯一模型 `gpt-6-astra`，Responses WebSocket 持久会话与同模型 HTTP fallback。持续复核以候选版本合并调度，不按 token 单独推理；EOS 必须执行最终复核。请求有唯一身份、generation/version fencing、去重、上下文恢复与用量收据。GPT 只能选取 ASR 提供的原始 span；不能凭常识补词、翻译、润色、总结或扩写。没有替代证据时保留现有可信文字及内部不确定状态。GPT 失败不删除原音/文字，错误按 authorization/permission/quota、connection、429 区分并走统一 failover。

## 不可退化的数据与输入契约

- PCMJournal/SQLite/Keychain 结构保持；原音保存不依赖 ASR/GPT/目标输入框。
- 只删除原音时保留全部文字及用户修改稿。
- Apple 进入统一候选/发布路径；断网不停止录音保存。
- UTF-16 增量派发；不整框重写、不自动发送/回车、不确定结果不重放。
- 旧 generation 不得覆盖新结果；用户编辑和目标身份校验优先。

## 当前证据边界

代码路径与离线协议模拟可以验证单 provider fanout、generation、GPT review、failover 和存储契约；不能证明供应商真实权限、真实准确率、端到端延迟或实际账单。24 条冻结人声只准备 A Qwen+GPT、B AssemblyAI+GPT、C Soniox+GPT，共 72 个独立流程；无 API 时全为 NOT_RUN。Gatekeeper、公证及真实应用输入仍按各自状态单独报告。

## 官方能力来源

- https://help.aliyun.com/zh/model-studio/qwen-asr-message-websocket-api
- https://www.assemblyai.com/docs/streaming/api-spec/streaming-websocket
- https://docs.soniox.com/stt/models
- https://developers.openai.com/api/docs/models/gpt-6-astra
- https://developers.openai.com/api/docs/guides/websocket-mode
