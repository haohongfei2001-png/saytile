# V1 单 ASR + GPT-6 工程收口路线

当前决定（2026-11-07）：One ASR Expert + One GPT-6 AI Core + SingleTranscriptEngine。双 ASR 并行默认链已废止。

| 优先级 | 工作 | 完成证据 | 阻断/后续 |
|---|---|---|---|
| P1 | 单 ASR 语言注册与选择 | LanguagePreference/LanguageProfile/ASRModelRegistry；每代仅一个 active streaming model | 首次 Auto 仍依赖 locale 先验；语言分类质量待真实使用观察 |
| P1 | GPT 失败统一 failover | 持久 review client 错误进入 FailureReporter；429 minimumRetryDelay 作用于 EOS | 需模拟 401/403/402/429/timeout 故障注入回归 |
| P1 | 英文数字/金额保护 | 基数、序数、小数及货币表达纳入 protected signature | 需验证常见口语数字表达，不扩大语义能力声明 |
| P1 | 评测完整性 | PCM frame receipt + EOF + session terminal + run state；不再要求词尾等于 WAV 末尾 | 真实 provider EOS/final drain 仍需凭据验证 |
| P1 | 24 条真实单 ASR 对照准备 | A Qwen+GPT、B AssemblyAI+GPT、C Soniox+GPT；72 次，NOT_RUN | 等 Key、模型权限和单独费用/上传授权 |
| P1 | 前台输入 | 保留安全所有权契约，先修复 foreground probe -5 | 真实 ChatGPT/Codex WebKit 仍未验证 |
| P1 发布 | Developer ID、公证、staple、Gatekeeper | 独立签名、公证与隔离首次安装收据 | 无发行方凭据时 BLOCKED |
| P2 | 暂停后唤醒状态 | 已修复：睡眠/会话失活不再覆盖用户主动暂停状态，并增加纯状态回归 | 真实内核睡眠复测仍待后续机器窗口 |
| P2 | 长期驻留 | 保留后续观测 | 72 小时观察不伪装完成 |

禁止重新研究架构、改生产 main、覆盖 RC1/no-api.9.1、收费调用、私人录音上传或削弱数据/输入保护。
