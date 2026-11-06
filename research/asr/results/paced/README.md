# 已完成的 Apple paced 文件回放

12 条，沿用冻结 latency-manifest.json；固定 zh-CN，按音频节奏投喂 100 ms 批次。见 summary.json 与原始 JSONL。

首可读时间从回放开始计算；stable_after_input_seconds 从 EOF 计算，不一定从最后真实语音结束计算。此路径绕过生产 WebRTC、CaptureWorker、麦克风和目标输入，不能报告为 Saytile 端到端或云端首字延迟。n=12 的 P95 只是样本统计，不是可靠总体尾延迟。

运行器：../../../asr-2026-11-06/scripts/AppleReplay.swift；配置及模型来源与 ../direct/run.json 的 Apple 基线一致。
