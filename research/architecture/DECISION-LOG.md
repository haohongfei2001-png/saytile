# 架构决策记录

## 2026-11-07：单 ASR 专家 + 唯一 GPT-6 AI 核心（当前有效）

1. 正式废止两个或更多 ASR 同时接收同一录音的生产默认路径。每个 recordingID/audioEpoch 固定一个 ASR provider/model。
2. 语言偏好：Auto（默认）、Chinese、English、Chinese-English Mixed。显式偏好优先；Auto 使用近期语言观察与 macOS locale 先验；不能可靠判断时走 Apple 本地能力/保留原音，不盲选云模型。
3. 初始候选映射：Qwen 中文、AssemblyAI 英文、Soniox 混说；没有真实 24 条对照结果前不宣称任何模型最优。
4. 唯一 GPT-6 Astra 文本核心。无原生音频输入；不得把 GPT 的常识补全当声学证据。只允许忠实、来源可验证的 span 选择。
5. Apple SpeechAnalyzer 是本地与云故障接替，不是并行专家。
6. 原音、文字、用户修改稿和外部派发账本独立；不因 GPT/ASR 失败丢失，未确认外部结果不重放。
7. 配置迁移保留 provider/model/UUID/Keychain 授权身份；不静默换 Key、不自动提升 consent。
8. GPT 运行期错误进入统一 failover；429 最低 60 秒约束同样适用于 EOS。
9. 24 条冻结语音只比较 A Qwen+GPT、B AssemblyAI+GPT、C Soniox+GPT；共 72 次完整流程，未授权时 NOT_RUN。
10. 生产 main、RC1 和 no-api.9.1 不被本分支修改；签名/公证与真实云验收分别判定。

历史双专家决策仅作为此前版本记录，不再是当前实现目标。
