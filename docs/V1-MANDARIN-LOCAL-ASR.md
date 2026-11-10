# 本地普通话识别 · M5 原生候选

产品源码 `aa68eb5f82a767973ff5dcdc15932cb823e4afd9`。四种引擎均已在 Apple M5、24 GiB、macOS 27 的签名原生窗口实际运行。屏幕文字由当次唯一的 ASR 生成，采集和原音写盘独立于识别。Zipformer 为研究候选，正式目录提供 Apple、Streaming Paraformer 与 Qwen 0.6B。云端模式保持原有授权路径。

**安装包** 为 61,601,241 字节。Developer ID 签名和升级演练通过，Gatekeeper 对此未公证构建返回拒绝。[DMG 与安装说明](../deliverables/mandarin-local/) · [原生窗口实录](../evidence/mandarin/final/zipformer-window.mp4) · [产品源码及权重指纹](../evidence/mandarin/final/build-receipt.json)

## 评测方法

统一评估 420 个不同参考的公开人声样本，另含 20 次同源扰动。所有模型共享 16 kHz 单声道音频、量化文件哈希、参考文本及规则。参与评测的第三方权重按需加载。公布的原始 JSONL 可逐句追溯。CER 使用仓库 NFKC、casefold、数字内标点保留以及逐字符最短编辑距离；没有繁简、数字或术语同义替换，空结果按全句漏字计算。中英混说另计中文逐字、英文逐词 MER。数字、否定词、金额、时间、术语的字面保留次数在机器结果中逐类给出，等价读法需要单独判断。[来源与授权](../evidence/mandarin/SOURCES.md) · [复现步骤](../scripts/mandarin/README.md)

模型直通结果来自实际量化模型的完整音频会话。产品档案结果经过采样转换、VAD、PCMJournal、唯一 ASR、融合发布和 SQLite。两类批量回放为了取得质量使用加速喂入。首次显示、修订与定稿耗时取自另外 15 条原速、每条冷启动的签名 AppKit 窗口。这 15 条分布在朗读、自然普通话及中英混说，每路各有 5 条达到 10 秒。首字取 −55 dBFS 持续声起点后的非标点文本；有效更新要求本帧引入参考中出现的相邻双字。P95 使用最近秩，因此 15 条中的 P95 是本次最大值。活动区间的末端用实际音频能量估算，EOS 延迟以播放完文件到识别任务排空计。[窗口原始观测](../evidence/mandarin/final/panels/)

## 公开成绩与具体权重

icefall 的中文 Large CTC greedy streaming 报告 AISHELL-1 dev/test 为 1.71% / 1.97%，WenetSpeech net/meeting 为 10.62% / 8.13%。所指原始 checkpoint 的流式 CTC 评分文件名包含 epoch-999、avg-1、chunk-32、left-context-256。模型用 FP16 训练选项，论文/配方表的成绩不代表部署版 INT8。发布的 INT8 ONNX 单文件为 162,290,887 字节，即 154.77 MiB，含词表共 162,311,515 字节。字节、转换版本与 SHA-256 均在清单内。sherpa-onnx v2.0.1 使用 Apache 2.0，ONNX Runtime 使用 MIT。维护者说明转换权重跟随原 checkpoint，并在回复中举了 XL 的例子。这里使用的 Large checkpoint 和转换仓库没有可核实的权重商用授权。[icefall 配方](https://github.com/k2-fsa/icefall/blob/master/egs/multi_zh-hans/ASR/RESULTS.md) · [sherpa 官方模型说明](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-ctc/zipformer-ctc-models.html) · [维护者说明](https://github.com/k2-fsa/sherpa-onnx/issues/3918#issuecomment-5754861224) · [固定权重记录](../evidence/mandarin/zipformer-provenance.json)

Qwen 团队模型卡在其公开评测表列出原始 0.6B 的 FLEURS-zh 2.88%、AISHELL-2-test 3.15%、WenetSpeech net/meeting 5.97% / 6.88%。本产品使用独立转换的 4-bit MLX 权重，FLEURS 子集与本地打分均不同。Apple 的本次系统资产和 sherpa 双语 Paraformer 的精确 INT8 转换缺少可直接配对的官方同口径分数。两者的本机结果与其他模型采用相同评分程序。[Qwen 模型卡](https://huggingface.co/Qwen/Qwen3-ASR-0.6B#evaluation) · [Paraformer 实际权重](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/tree/8e40c43232a1c5c66c82111efc5820d3accca11b)

FP32 和 INT8 转换在同一台 Mac 上使用相同的原生 sherpa CTC 助手、CPU、两线程、贪心解码、200 ms PCM、一致的末尾补齐与 token 表。AISHELL 子集共有 1,465 个参考字符，FP32 错 53 字（3.62%），INT8 错 50 字（3.41%）。100 段中量化后 4 段改善、1 段变差、95 段错误数持平。按语料分层的其他差异和两个精度的逐条输出已归档。[量化对照](../evidence/mandarin/quantization/)
