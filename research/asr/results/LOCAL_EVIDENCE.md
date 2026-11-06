# 本机既有实验：证据范围与评分核验

更新日期：2026-11-06。本文件整理已经完成的识别与审计，不代表新的模型实验或新的评分体系。

## 证据与语料

- 运行元数据：[direct/run.json](direct/run.json)。环境为 Apple M5、24 GiB 内存、macOS 27.0、Swift 6.4；准确率任务可能并发运行。
- 冻结全集：[manifest.json](../../asr-2026-11-06/corpus/manifest.json)；来源与许可记录：[sources.json](../../asr-2026-11-06/corpus/sources.json)。
- 全集 134 条：112 条未经扰动的真人录音，以及 22 条派生／控制样本（18 条扰动、2 条拼接连续样本、2 条合成负控）。不能称为 134 条独立自然语音。
- 本次直接识别只使用相同的 112 条真人录音：96 条 primary + 16 条 challenge。primary 为中文、英文、中英混说各 32 条；challenge 为刻意挑选的术语、数字等样本，不与 primary 合并排名。
- ASCEND 提供对话及真实中英混说；FLEURS 为朗读。两种语音风格和来源不完全对称。拼接样本不代表未经剪辑的自然长对话。
- 已完成的物理审计：134/134 WAV 存在，SHA-256、采样率和帧数均与全集 manifest 匹配；音频为单声道 16 kHz PCM16。
- 原始音频未提交仓库。Linux 位置为 `.test-data/asr/audio/`；Mac 位置由运行记录指定为 `~/.codex/saytile-asr-research-20261106/audio`。
- 全集 manifest SHA-256：`5a5d9809f016f4119c6e3e9d48ce8b62aecae8bb9a5ab050a73c9cb627f5407f`。
- `run.json` 的 `original_manifest_sha256` 指提取器输出的 **112 条真人子集**：`528fe5f064cf2ce1b89ac411c839099ba9f6751ae918735df50bc1cc263a6f9b`；它不是全集哈希。已按原提取器序列化规则确认其对应关系。
- 许可：ASCEND 为 CC-BY-SA-4.0，FLEURS 为 CC-BY-4.0；root 已于 2026-11-06 复核官方数据卡，链接及归属见 [README](README.md)。固定来源修订、下载 URL、归档 SHA-256 和字节数均保存在 `sources.json`，三个缓存归档此前均已通过实际哈希核验。

## 三组运行的完整性

| 运行 | 记录 / 独立 ID | error | 音频哈希缺失或不符 | 未知 ID | 未完整 final |
|---|---:|---:|---:|---:|---:|
| [Apple 固定中文](direct/apple-direct-fixed-zh.jsonl) | 112 / 112 | 0 | 0 | 0 | 1 |
| [Apple 按真值选语言](direct/apple-direct-oracle-locale.jsonl) | 112 / 112 | 0 | 0 | 0 | 0 |
| [本地 Qwen3-ASR](direct/qwen-direct.jsonl) | 112 / 112 | 0 | 0 | 0 | 0 |

这是 112 条录音的 336 次运行记录，不是 336 条独立录音；三个运行配置也不是三个不同模型家族。主样本均有非空文本。

Apple 使用 SpeechTranscriber。固定组全部采用 `zh-CN`；oracle 组对英文样本采用英文配置，使用已知语言标签，不能当成已实现自动语言路由。

Qwen 为本地 `mlx-community/Qwen3-ASR-1.7B-bf16`，修订 `e1f6c266914abc5a46e8756e02580f834a6cf8a7`，MLX Audio 0.6.4、MLX 0.32.4；自动语言、temperature=0、无 VAD、无热词／提示词。**它不是托管 Qwen Audio 3.1 message/streaming API；本地分数不能移植给该云服务。**

Apple 固定组唯一 `completely_final=false` 为 `fleurs-en-9833173223298420094`（primary/en）。其 `text` 比 `stable_text` 仅多末尾句号；现有评分忽略该句号，故不改变下面分数，但“零 error”不能表述为“全部完整定稿”。

## 已复算的主样本严格文本错误率

依据既有 [score.py](../../asr-2026-11-06/scripts/score.py) 复算，未新增评分实现。NFKC、大小写及标点规范化后，中文用 CER、英文用 WER、混说用 MER（汉字与英文词的混合单位）。不把繁简、数字写法、缩写或同义表达统一成语义等价文本。

| 运行 | 中文 CER，32 条 | 英文 WER，32 条 | 混说 MER，32 条 |
|---|---:|---:|---:|
| Apple 固定中文 | 120 / 1041 = **11.53%** | 480 / 644 = **74.53%** | 122 / 508 = **24.02%** |
| Apple 按真值选语言 | 120 / 1041 = **11.53%** | 61 / 644 = **9.47%** | 122 / 508 = **24.02%** |
| 本地 Qwen3-ASR | 71 / 1041 = **6.82%** | 36 / 644 = **5.59%** | 61 / 508 = **12.01%** |

分子为替换 + 删除 + 插入；分母为参考字符／词／混合单位数。可机读分解见 [direct/summary.json](direct/summary.json)。16 条 challenge 的原结果已保留，本摘要不将其扩展成新的总分或排名。

## 可支持与不可支持的判断

- 可支持：在这批小样本的直接音频识别中，本地 Qwen3-ASR 的三项错误率低于这两种 Apple 配置。Apple 固定中文的英文结果同时暴露语言配置问题；讨论英文引擎能力必须一并报告 oracle 的 9.47%。
- 不能据此宣布全球最佳、托管 Qwen 3.1 更优，或估计一般用户的准确率。每类仅 32 条 primary，语料分布有限，reference 沿用上游，未完成全量人工听审；百分比不是“整句正确率”。
- 本批为 `offline_file_processing_not_realtime`，没有经过 Saytile 真实生产 VAD 切段，也没有验证麦克风、目标输入框与稳定前缀派发路径。文件处理耗时和事件到达时间不能冒充实时首字或停说到定稿延迟；并发运行还会影响耗时。
- 旧实体评分用规范化子串匹配，可能把 SQL 在 SQLite 内视为命中，亦不能可靠统计重复实体。关键实体标注稀少且未完整人工审定，不能作数字、否定或专业术语可靠性排名。插入错误也不自动等于已确认的幻觉。
- 繁简、数字格式及英文缩写处理会影响严格错误率；本阶段未另建规范化分数，不能将全部文本差异解释为内容听错。
- 另有后续归档的 12 条 Apple paced 文件回放，见 [paced](paced/README.md)，独立记录采样与发送节奏，不与本表离线准确率混为同一条件。

## Whisper 的保留状态

既有 [Whisper 结果](../../asr-2026-11-06/results/whisper-large-v3-int8.jsonl) 按用户最新要求主动停止在 55 条，属于缩减研究范围，**不是模型故障**；保留记录但不纳入本次横向排名。

更早的 `attempts/whisper-pyav19-decode-failure.jsonl` 为 `metadata_errors` 参数不兼容引起的解码基础设施失败，应与本次主动停止明确分开，不能计作模型识别错误。
