# Saytile 双专家 + GPT-6 核心引擎开发路线

更新：2026-11-07。新路线覆盖旧版自适应单主模型路线。

## Stage 1 — 架构与分支收敛（P0）

- 同步 PR #5 base 至 PR #4 最新 HEAD；保留 RC2 最新修复与验收记录。
- 固定双平等专家 + 一个 GPT-6 Astra 的配置契约。
- 移除 Gemini audioReview、Scribe finalASR 作为默认链路；保留旧枚举/数据库兼容，不再启用。
- 将 MultiRecognitionCoordinator 收敛为 SingleTranscriptEngine；旧类型名只做内部兼容过渡。
- GPT 调用改为 Responses streaming，短窗口合并事件，旧证据结果丢弃。
- 用户 UI 移除多模型仲裁与识别模式选择，默认唯一 transcript。

验收：默认恰好两路实时 ASR + 一个 GPT-6；配置不允许多个 GPT 核心；两路收到相同 PCM block；GPT 结构化输出只能引用候选。

## Stage 2 — 模型对照（P0）

复用 112 条现有语音、336 条 Apple/Qwen 历史结果，第一轮 24 条代表性样本。音频只在 Mac 本地；未经明确授权不上传云服务。

| 配置 | 对照 |
|---|---|
| A | 中文专家 + GPT-6 |
| B | 英文专家 + GPT-6 |
| C | 中文 + 英文专家 + GPT-6 |
| D | Soniox v6 + GPT-6 |
| E | 中文 + 英文 + Soniox v6 + GPT-6 |
| F | GPT-6 Astra 原生音频 + ASR 证据 |

F 由于 GPT-6 Astra 官方 API 明确 Audio not supported，标记 NOT AVAILABLE，不伪造执行。可另行比较 GPT-Live-Transcribe / GPT-Realtime 作为独立音频模型，但不能把它们称为 GPT-6。

指标：中文 CER、英文 WER、中英混说 MER、术语、数字/金额/时间/否定错误、首次可见文字延迟、讲话中修正收益、结束后最终修正延迟、GPT 新增错误率、最终派发正确率。所有配置按同一音频配对，按中文/英文/混说分层。24 条接近时扩展至 112 条。

依赖：已有音频与参考文本、相应服务 Key、模型账户权限、明确音频处理授权和费用授权。缺少任何服务授权时，只完成已授权的子集并报告缺口，不阻塞架构开发。

## Stage 3 — SingleTranscriptEngine 核心实现（P0）

- 两路完整音频并发，不作预切分。
- Apple SpeechAnalyzer Candidate ingress。
- 单一 GPT-6 Responses streaming reviewer。
- 280ms coalescing、evidence version、generation fencing。
- 唯一 transcript preview/stable/final revision。
- EOS 后最终 GPT 复核。
- 用户编辑和 UTF-16 外部输入账本保护。
- 断网保留 PCMJournal，云端恢复幂等续识别。

## Stage 4 — 质量和长期运行验收（P0）

自动测试：专家乱序/重复/迟到、GPT 迟到、GPT 新证据版本、否定数字保护、混说回归、用户编辑保护、目标窗口变化、外部重复输入、断网/恢复、长时间录音、磁盘空间、睡眠唤醒、权限撤销、PCMJournal 恢复。

真实质量验收与 CI 分开：必须报告真实云调用结果、参考文本审校、费用、首显/稳定/完成 p50/p95 和关键错误。无云数据不作质量领先声明。

## Stage 5 — 发布收敛（P0）

Developer ID 签名/公证、升级/回滚、隐私/权限说明、默认关闭云端、独立 Keychain、每服务授权、调用与费用账本。生产 main/RC1 仅在用户明确批准后变更。
