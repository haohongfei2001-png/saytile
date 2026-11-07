# 单 ASR + GPT-6：BYOK 与真实质量验收

用户设置仅提供语言偏好：Auto、中文、English、中英混说。应用按 LanguageProfile/Registry 选择一项 ASR；用户不需要选择模型。当前候选：Qwen（中文）、AssemblyAI（英文）、Soniox（混说），均未获质量冠军。GPT-6 Astra 是唯一 AI 核心。Apple 是本地/故障接替。

每段录音只上传给一个 ASR。连接检查只检查当前语言所选 ASR 与 GPT-6 两项服务；Qwen 额外需要匹配地域的 Workspace ID。Key 只存 Keychain。配置/Key 变更不得静默改变旧录音授权。

## 真实质量实验

冻结 24 条：A Qwen+GPT、B AssemblyAI+GPT、C Soniox+GPT，最多 72 次流程。每次一个 ASR，完整音频；GPT 配置、上下文规则和评分一致。记录 ASR raw、GPT final、GPT 新增/修复错误、中文 CER、英文 WER、混说 MER、数字/金额/时间/否定/术语关键错误、首字和最终确认延迟、请求与 usage/cost。

当前无 API Key：A/B/C 全部 NOT_RUN。历史 Apple 与本地 MLX Qwen 结果不冒充云端结果。未执行指标必须为 null/NOT_RUN，不能填 0 或推断排名。

## 连接与生产状态

配置存在、Keychain 凭据存在、真实鉴权、模型权限、用户数据处理授权、实时转写、质量通过、普通发行是独立状态。首次连接检查使用内置合成语音，不用麦克风/历史录音；没有单独授权不发收费请求。Gatekeeper、公证、签名与长期稳定性分别验收。
