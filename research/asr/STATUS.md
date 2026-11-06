# Saytile ASR 研究状态与接续入口

更新：2026-11-06。**选型已裁决，实施规范已完成；当前 PR 是研究与工程决策交付，不是生产引擎替换。**

## 当前唯一方向

- 主方案：Soniox `stt-rt-v6` 单云端实时引擎，同时提供预览和稳定文字；Apple 保留离线备用；不默认双模型。
- 最新用户指示已经停止扩大公共 benchmark、下载更多语料和多供应商横评。不要按旧计划继续全矩阵实验。
- 先读 [DECISION.md](DECISION.md)，然后执行 [IMPLEMENTATION.md](IMPLEMENTATION.md)。[VENDORS.md](VENDORS.md) 说明来源层级与接口。
- 独立分支：`research/asr-quality-2026-11-06`；[PR #4](https://github.com/haohongfei2001-png/saytile/pull/4)。
- 生产基线：`a352a1c812c33388a1a908f21ecde30da80ad1cd`，RC1 / 已合并 PR #3。研究没有修改 `Sources/`、正式包、私人录音或个人数据库。

## 已完成且有文件证据

| 阶段 | 完成状态与入口 |
|---|---|
| 中断恢复 | 旧 Linux checkout、134 条语料 manifest 与实际文件、Mac Qwen 权重与环境均恢复核查；未假称部分 base64 文件就是完整传输。后续由 Mac 直接下载固定来源，已停止聊天传音频方式。 |
| 原始语料完整性 | 134/134 的 WAV hash / rate / frames 匹配；其中 112 原始真人、22 派生或控制。来源、修订、归档 hash 见旧 corpus/sources.json。 |
| 已完成直接识别 | 同 112 条真人 × Apple 固定中文、Apple 已知语言对照、本地 Qwen3-ASR-1.7B = 336 条输出；严格评分及边界见 [LOCAL_EVIDENCE.md](results/LOCAL_EVIDENCE.md)。 |
| Apple paced 回放 | 12 条按 100 ms 节奏发送的文件回放，全部完整 final；见 [paced](results/paced/README.md)。绕过生产 VAD，不是云端或麦克风端到端延迟。 |
| 生产源代码审计 | 固定 zh-CN、WebRTC 门控、30 秒上下文重建、retired 取消、单 active_attempt、稳定派发与目标保护，见 [PRODUCTION_AUDIT.md](PRODUCTION_AUDIT.md)。 |
| 最小 VAD 实机检查 | 已在 Mac 执行原片段、79 秒重复跨两次强制边界、活动短尾共三次；该三例无样本遗漏/重叠，尾部 43 样本正常 flush。见 [vad-probes](results/vad-probes/README.md)。不含 ASR。 |
| 公开证据与现行接口 | 核验 Pipecat / Verli 的适用范围，以及 Soniox、Qwen、OpenAI、ElevenLabs、豆包现行接口。没有将营销或旧型号分数改标为当前型号实测。 |
| 技术裁决与实施 | 唯一方案、条件备选、具体 Swift / WS / 保存 / 派发 / 恢复 / 有限验收要求已写入 DECISION 与 IMPLEMENTATION。 |

## 明确没有完成、也不应伪称完成

- 没有云 ASR 实际调用：未发现可使用的授权服务凭据，没有新开付费服务、充值或无上限调用。
- 没有 Saytile + Soniox v6 的实际 CER / WER / MER、首字或大陆网络延迟成绩。v5 的公开 TTFS 不是 v6 首字。
- 三个 VAD probe 不执行麦克风、重采样、CaptureWorker、完整识别或外部输入。
- Whisper 运行已按用户方向变更主动停止在 55 条，保存但不纳入完整排名；先前 PyAV 解码故障另存，不算模型质量失败。
- RC1 没有替换为实验引擎。后续 Codex 按实施规范开发并做一次有限真连接验收，不能将研究结论当作部署已完成。

## 持久化与本地定位

- GitHub 阶段提交：`1db3a94` 保存恢复的脚本与语料索引；`fdaaac4` 保存 336 条已完成输出；`7943d78` 保存实机切段审计、paced 回放与证据摘要；最终裁决以本分支后续提交为准。
- 旧记录保留在 `research/asr-2026-11-06/`；它是历史证据，不是继续扩建 benchmark 的任务清单。
- Linux checkout：`/workspace/scratch/ecf2608272fb/saytile-research`；音频：其 `.test-data/asr/audio/`（134 条）。
- Mac 研究根目录：`/Users/hhf/.codex/saytile-asr-research-20261106`；独立 checkout 为 `repo/`，112 条真人 WAV 在 `audio/`，固定来源归档在 `corpus-cache/`，probe 原音输出在 `vad-probes/`。
- 原始/派生音频、模型权重、缓存和秘密均不提交。公开参考文字与来源按各自数据许可证归属，见 [results/README.md](results/README.md)。

下一步是 **Codex 实现 Soniox 候选**，不是重新研究排行榜。没有密钥也能完成协议 fixture 与本地实现；真实云端验收缺口必须诚实保留，不能要求用户现在进行真人测试来代替工程工作。
