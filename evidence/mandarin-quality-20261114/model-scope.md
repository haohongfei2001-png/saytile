# 本轮候选与运行边界

Apple SpeechAnalyzer 使用 macOS 提供的简体中文转写资源。系统管理安装和授权。第三方模型的文件、长度、提交和逐文件 SHA-256 随 App 放在 `Contents/Resources/LocalASR`。权重留在各自的应用资料目录，DMG 含所需原生运行库。

| 模型 | 本机运行与校验 | 来源 |
| --- | --- | --- |
| Apple 中文 | 系统 SpeechAnalyzer，逐步返回候选。每个应用身份须完成资源准备。 | [Apple SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) |
| Streaming Paraformer | 真流式 ONNX INT8，237,202,501 字节。模型卡标注 Apache-2.0。 | [固定模型版本](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/tree/8e40c43232a1c5c66c82111efc5820d3accca11b) |
| Qwen3-ASR 0.6B | 原生 MLX 4-bit，712,777,119 字节。按音频块增量重解码，句末以同一个引擎定稿。 | [固定量化权重](https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit/tree/bc441bd1e4295c1f42d9879f056049a925b6e013) |
| Qwen3-ASR 1.7B | 同样的分块增量与 MLX 工作进程，2,229,873,245 字节。候选权重与原始模型卡均标注 Apache-2.0。 | [固定量化权重](https://huggingface.co/aufklarer/Qwen3-ASR-1.7B-MLX-4bit/tree/d4f9fa3bb45489219f0fcbec671c92d9c1a68fb6) · [原始模型](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) |

本轮沿用原先做过原生测试的候选范围。Zipformer 中文 INT8 有真流式运行时，但所用 Large 检查点和 INT8 导出未找到明确的商业权重许可，运行库的 Apache-2.0 不涵盖第三方权重。原始文件与维护者答复已在仓库留档。[Zipformer 权重来源记录](../mandarin/zipformer-provenance.json)

FluidAudio 的离线档案模型保留以往测试结果。实际解码器必须在讲话中产生真实文字才能成为实时默认。运行库版本与第三方许可见[发行说明](../../THIRD_PARTY_NOTICES.md)。已发布的逐文件清单和此次实测二进制摘要见[机器记录](bench-identity.json)。

另核对了 Fun-ASR-Nano-2512 和 FluidAudio Parakeet EOU。前者上游公开的增量 SDK 使用 Python / vLLM，另有支持 macOS 的 GGUF 移植；本轮未取得该移植在 Saytile 内按实际速率输出中文临时字的证据。后者原生增量模型限于英语。两者均未占用本轮中文产品对照的名额，厂商的中文分数也未计入上述结果。[Fun-ASR 增量入口](https://github.com/QwenAudio/Fun-ASR#streaming-sdk) · [macOS 移植的模型说明](https://github.com/handy-computer/transcribe.cpp/blob/main/docs/models/fun-asr-nano-2512.md) · [FluidAudio 原生模型能力](https://github.com/FluidInference/FluidAudio#highlights)
