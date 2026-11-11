# 第三方与许可证边界

本交付没有打包 Apple SDK、语音模型权重、FluidAudio/WhisperKit/GRDB 源码或字体文件。

历史研究中的组件许可描述作为历史信息保存。正式工程需要对所选具体版本的代码、模型权重、依赖和分发条件分别复核。本交付不替代许可证审查。

公开仓库与授予开源许可证不是同一决定。本轮未添加 MIT/GPL 等项目许可证，不替用户作出新的开源授权。

## 原生 V1 已使用

- Apple AppKit / SwiftUI / AVFoundation / Speech / CoreAudio / ServiceManagement：系统框架，App 未包含 SDK 或系统语音模型；语言资源由 Apple AssetInventory 管理。
- SQLite：调用系统 libsqlite3；SQLite 属公有领域，不另捆绑二进制。
- WebRTC VAD：代码位于 `Sources/CAudio/webrtc/`，来自 wiseman/py-webrtcvad 的 vendored WebRTC；完整 BSD 许可及 wrapper MIT 许可见 `Sources/CAudio/WEBRTC-LICENSE.txt`，同时随 App Resources 分发。
- 引入来源包：`https://codeload.github.com/wiseman/py-webrtcvad/tar.gz/refs/heads/master`（2026-11-06 获取）；SHA-256 `4d585f73cdfac59e3df049745432079d09b896cef7878f4055f96ec43d01d211`。工程直接固定提交全部所需源码，构建不再拉取可变 master。
- `AudioRing.c`、桥接 VAD 包装器与 Swift 原生模块为 Saytile 本轮实现。

## Local ASR development candidate

The installer contains recognition runtimes and a compiled Metal shader library. Model weights are installed separately from the revision and SHA-256 manifest in the app.

| Component | Source | Version / terms |
|---|---|---|
| Apple SpeechAnalyzer | Apple Speech framework, system AssetInventory | macOS system component and Apple-managed Mandarin transcription assets |
| sherpa-onnx | https://github.com/k2-fsa/sherpa-onnx | v2.0.1 Apache-2.0; ONNX Runtime 1.28.2 MIT and its third-party notices |
| Streaming Paraformer bilingual INT8 | https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en | FunASR / k2 export, model card Apache-2.0 |
| MLX and speech-swift | https://github.com/soniqo/speech-swift | a57702e6, Apache-2.0; mlx-swift 0.31.4 MIT; compiled shader from v0.0.29 |
| Nemotron 3.5 ASR Streaming 0.6B | https://huggingface.co/aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-8bit | NVIDIA, converted by aufklarer; OpenMDW-1.1 |
| Qwen3-ASR 0.6B and 1.7B | https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit and https://huggingface.co/aufklarer/Qwen3-ASR-1.7B-MLX-4bit | Alibaba Qwen, converted by aufklarer; both Apache-2.0 |
| FluidAudio | https://github.com/FluidInference/FluidAudio | 653386fa, Apache-2.0 |
| FluidAudio Paraformer Large INT8 | https://huggingface.co/FluidInference/paraformer-large-zh-coreml | Alibaba FunASR; FluidInference Core ML conversion. The card defers to upstream Paraformer-large terms |
| FluidAudio SenseVoice Small INT8 | https://huggingface.co/FluidInference/sensevoice-small-coreml | FunAudioLLM / Alibaba, FluidInference conversion; upstream FunASR Model License v1.1, included in LocalASRLicenses. Evaluation candidate; commercial distribution requires review of the upstream terms |

The Mandarin diagnostic audio is from Google FLEURS (CC BY 4.0). The app does not ship the benchmark recordings. The paired manifest preserves the row, reference, attribution, revision and hash.

Research-only Chinese streaming Zipformer2-CTC: sherpa-onnx v2.0.1 (Apache 2.0), CPU Core native arm64, CTC greedy. Converted weights: https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-ctc-zh-int8-2025-06-30/tree/f29132af655b91f258800df19c5b5d9b9281a5cd . The converter points to https://huggingface.co/yuekai/icefall-asr-multi-zh-hans-zipformer-large/tree/87163dfd71478fe2397af74b841d7b666c90c665 . Neither pinned repository supplies a commercial weight grant. The maintainer refers to the original checkpoint in https://github.com/k2-fsa/sherpa-onnx/issues/3918 . Do not infer a weights license from the runtime; excluded from consumer choices and never shipped as weights. Network manifest locks each file to the upstream revision and SHA-256.

The integrated Developer ID distribution embeds Sparkle 2.10.1. Its copyright notices and MIT license are included in Resources/SPARKLE-LICENSE.txt. The release artifact is pinned by SHA-256 in scripts/prepare-updater.sh. [Upstream release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1)
