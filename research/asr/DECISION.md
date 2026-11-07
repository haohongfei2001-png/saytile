# 单 ASR + GPT-6：正式识别决策

更新：2026-11-07。当前权威架构见 [FINAL-ARCHITECTURE](../architecture/FINAL-ARCHITECTURE.md)。本决定覆盖此前双 ASR 并行方案。

| 用户语言场景 | 初始 ASR 候选 | 选择原则 |
|---|---|---|
| 中文 | Qwen Audio 3.1 Message | 冻结语料中文 CER 与关键语义错误表现 |
| English | AssemblyAI Universal-3.6 Pro | 冻结语料英文 WER 与关键语义错误表现 |
| 中英混说 | Soniox STT v6 | 句内 code-switching 的 MER 与关键错误 |
| 所有场景 | 唯一 GPT-6 Astra | 只选择/修订有来源的 ASR span；不听原音、不生成无证据新词 |

Apple SpeechAnalyzer 保留离线与网络故障接替。每个录音只有一个活动云 ASR；同一音频块不重复上传到其他专家。配置改变作用于下一段，不切换当前录音。

## 冻结真实对照

使用既有冻结 24 条（中文 8、英文 8、中英混说 8），不更换 ID、音频或参考：A Qwen+GPT、B AssemblyAI+GPT、C Soniox+GPT。最多 72 次独立完整流程。每次同一 GPT 配置/上下文/评分，记录 raw ASR 与 GPT final、GPT 新增/修复错误、关键数字/金额/时间/否定/术语错误、CER/WER/MER、首字/最终确认延迟及实际 usage/cost。

当前没有 API Key，三组全部 NOT_RUN；不得伪造准确率、延迟、请求量或费用。历史 Apple/本地 Qwen 结果只作历史基线，不能替代三家云服务实测。
