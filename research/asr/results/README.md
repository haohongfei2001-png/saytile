# 已完成证据与材料归属

| 内容 | 入口 | 解释边界 |
|---|---|---|
| 112 条真人 × 3 个直接识别配置 | [LOCAL_EVIDENCE.md](LOCAL_EVIDENCE.md)、[direct/summary.json](direct/summary.json)、[run.json](direct/run.json) | 小样本，绕过生产 VAD；不等于三个云模型的横评。 |
| Apple 12 条 paced 文件回放 | [paced](paced/README.md) | 首预览与 EOF 后定稿独立统计；不等于生产/云端/麦克风延迟。 |
| 生产 VoiceSegmenter 三次实机 probe | [vad-probes](vad-probes/README.md) | 两次 30 秒强制边界和活动短尾已检查；未执行 ASR。 |
| Whisper 55 条部分输出 | [历史结果](../../asr-2026-11-06/results/whisper-large-v3-int8.jsonl) | 按最新用户方向主动停止；不纳入完整排名。 |

公开证据选择性快照见 [public-evidence-snapshot.json](public-evidence-snapshot.json)，Pipecat 表格已固定到来源提交；它不是新增本地横评。

## 来源与许可

本研究使用 **CAiRE / HKUST 的 ASCEND** 与 **Google 的 FLEURS** 已公开材料。2026-11-06 核验其官方数据卡：

- [ASCEND 数据卡](https://huggingface.co/datasets/CAiRE/ASCEND)：[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)，自然对话及中英混说；固定修订 `737e9800ae31be9932ba8464c80366559bd28424`。
- [FLEURS 数据卡](https://huggingface.co/datasets/google/fleurs)：[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)，朗读语音；固定修订 `70bb2e84b976b7e960aa89f1c648e09c59f894dd`。论文：Conneau 等，2022，[FLEURS: Few-shot Learning Evaluation of Universal Representations of Speech](https://arxiv.org/abs/2205.12446)。

固定 URL、归档 byte 数、SHA-256、选中 ID、源转写和 WAV hash 分别记录于 [sources.json](../../asr-2026-11-06/corpus/sources.json) 与 [manifest.json](../../asr-2026-11-06/corpus/manifest.json)。引用材料保留各自上游许可与归属，不因本仓库代码许可证而重新授权。

处理改动：抽样、解码为 16 kHz mono PCM16；原始 112 条没有人为语音扰动，其他 22 条有显式派生标注。三次边界 probe 另标记同片段重复与截断，只用于控制流。识别假设文本来自对应模型，并非手工修订后的 gold。

原音与派生 WAV 均未公开提交；位置见 [STATUS](../STATUS.md)、direct/run.json 和 vad-probes/environment.json。现有文件已核验，无需重复下载或经聊天搬运。没有私人录音或密钥进入这些结果。
