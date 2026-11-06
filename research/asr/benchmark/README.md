# 有限研究工具存档

当前工作以 [技术裁决](../DECISION.md) 与 [实施规范](../IMPLEMENTATION.md) 为准。用户已要求停止扩大公共 benchmark；本目录不是继续下载或全量跑模型的任务。

- `production_vad_replay.swift` / `run_production_vad_probe.sh`：仅编译原生产 VoiceSegmenter 与 WebRTC，执行已完成的三个目的明确的控制流检查。运行方式与实际报告见 [vad-probes](../results/vad-probes/README.md)。
- `extract_originals.py`：从已固定的合法来源归档恢复旧 manifest 中 112 条原始真人音频；已有 Mac / Linux 文件，默认不重复提取或下载。
- `run_qwen_mlx.py`：已经完成的本地 Qwen3-ASR-1.7B 直接识别运行器；其结果不是托管 Qwen Audio 3.1。
- `ASRInterfaces.swift`：早期类型草图，包含本轮未采用的多阶段扩展。生产只实现 IMPLEMENTATION 中最小单引擎接口。

旧语料、原始 Apple runner 与 scorer 保留在 `../../asr-2026-11-06/`。音频、权重、缓存与密钥不进 Git；文件处理倍速不能称为实时延迟。
