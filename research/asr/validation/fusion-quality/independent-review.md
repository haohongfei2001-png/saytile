# 融合协调器与仲裁证据独立审查

2026-11-06，PR #4 工作树。审查 `MultiRecognitionSession.swift`、`PrecisionReviewClient.swift`、`RecognitionFusion.swift` 与 Store 的发布、投递证明、删除和 usage 路径。使用独立 `/tmp/saytile-fusion-input` 构建及合成 SQLite/PCM fixtures；未读取私人录音，未请求凭据、上传或调用真实服务。本报告不证明真实识别准确率、供应商线上延迟或融合增益。

本轮发现并修复的重点：

| 问题 | 根因与处置 | 独立证据 / 当前边界 |
|---|---|---|
| P1：必需专家失败后旧稿仍可预留外发 | 旧 proof 只比较 candidate IDs，失败不改变这些 IDs；新 Store 完整重算又把 coordinator 收紧到已预留前缀的合法决定视为过期。Store 现核验必需 run 状态，认可安全收紧，预留事务再次拒绝失败源。 | **亲跑修前 red / 修后 green**，见下列两条隔离序列。 |
| P1：新声学冲突到达后，旧无 selections 提案可被赋予新 proof | 旧校验只检查提交的来源子集；新的冲突源没有进入该提案的校验，却进入 proof 的 current IDs。Store 现对当前有效完整证据集合重算，过期提案 defer，不能更新 proof。 | 隔离序列：双专家“支付15元。”→生成旧提案→追加复听“支付50元。”→提交旧提案。当前结果 `published=false, deferred=true`，无可预留文本。此项未亲跑修前 red，不把代码审查冒称失败实测。 |
| P1：异步 await 后把未接受提案缓存为已发布 | 原 `publish` 无条件缓存 submitted proposal；Store 已 defer 的旧 `resolved` 状态可能覆盖新状态，干扰复核和完成判断。现只缓存非 nil 的 `acceptedProposal`，且 evidenceVersion 必须仍匹配；Store 返回事务校验后的实际提案。 | 最终代码只读复查通过；并发协调器运行由父线统一回归，不能把本项代码复查单独称为调度穷举证明。 |
| 质量/延迟：新增真实词对齐不触发复核 | 去重签名原来遗漏 tokens、timingGranularity、language。现 canonical candidate 保留来源 run 和全部语义/时间证据，剥离通知 ID、sequence、createdAt；相同语义重复通知不会增加请求。 | 最终签名与调用路径已读；父线负责相应 coordinator 回归。 |
| 审计缺口：被拒绝的 AI 决策丢失 | 现 `ModelUsageRecord.arbitrationResponse` 保存请求 candidateIDs、请求时局部 confirmedPrefix、原始解码 decision；在 rebase/validation 前落盘。旧 payload 的缺省值为 nil。 | 4 项新增审计测试通过；详见下文。此字段不是 HTTP/wire 报文，也不赋予发布权。 |

**失败源两条独立复现。** `/tmp/saytile-fusion-failure-review.swift` 使用每次新建的合成数据库；无麦克风、AX、剪贴板或外部 App 操作。

1. 双专家一致稿已发布 → 必需 run 标 failed → 在 coordinator 撤回之前 reserve。修前得到 `支付15元。`；修后 `NONE`。
2. 新数据库重复前置条件，但先提交 `stableText=reservedPrefix=""` 的 failure hold，再 reserve。修前 hold 被 defer 后仍得到 `支付15元。`；修后 `NONE`。已预留文本始终受 durable cursor 保护，测试没有模拟撤销已发送内容。

修前输出：`/tmp/saytile-fusion-failure-before.log`、`/tmp/saytile-fusion-failure-hold-before.log`。修后输出：`/tmp/saytile-fusion-failure-after.log`、`/tmp/saytile-fusion-failure-hold-after.log`。新声学冲突序列：`/tmp/saytile-fusion-independent-review.swift` 与 `/tmp/saytile-fusion-independent-review.log`。本报告保留上述关键输出，避免仅靠临时文件表达结论。

**独立回归。** 命令 `SAYTILE_TEST_SCRATCH=/tmp/saytile-fusion-input SAYTILE_TEST_LOG=/tmp/saytile-arbitration-audit-tests.log scripts/test-native.sh --filter 'ArbitrationAuditTests|ArbiterEvidenceTests'`：**15/15 PASS**（4 项审计 + 11 项仲裁/复听契约）。新增审计用例验证：旧 JSON 无字段兼容；无效候选 ID/范围的拒绝决策与 usage 跨重启原样保留但不生成正文；只删原音保留审计；整条删除剥离审计文字、保留计费用量元数据，并在当前进程及重启后拒绝 late usage 恢复该文字。与原有 wire-contract fixtures 一样，以上全部是无云验证。

**收口复查。** `wholeCandidateSelectable` 复用实际 `audioInterval` 判定，未完成 Meta turn-progress 只能作文本佐证，不能借整句时长切片；所有 token 均传入，不截为前 256。实时/最终声学复核串行收口，同 PCM digest 只复用已完成结果，有新 PCM 则重新复核；未完成/不确定结果不冒充完成。最终未外发修订依赖 Store durable cursor，而非曾显示的稳定稿；显式用户稿与未保存草稿不被自动选择替换。父线的请求 prefix 已改局部快照，原 decision 先写 usage，再进行当前证据验证。

`modelRuns` 的完成/失败可与解码响应关联，表示该模型运行/校验阶段；它**不等价于外部实际送达**。是否成为稳定正文看 fusion decision/head，是否外发仍看 dispatch ledger。provider 文本/token 是适配器解码后的候选证据，未保存完整原始 wire；拒绝响应的解码审计现已实现，但尚无真实服务样本。当前已知上述 P1 已修并核对，整套测试、最终构建及 CI 由父线在统一 source checkpoint 验证。

证据已永久收拢到本目录：FailureReservationProbe.swift、AcousticConflictProbe.swift、failure-*.log、independent-review.log、arbitration-audit-tests.log。临时旧静态产物未嵌入唯一源码SHA；red表示开发期实际观察，不能扩大为某个发行包的测量。当前相同问题的可重跑回归已进入FusionRevisionSafetyTests及StoreFusionSafetyTests，最终统一源码SHA由delivery-manifest.json记录。
