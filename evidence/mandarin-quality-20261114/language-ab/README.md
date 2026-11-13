# 不强制中文时，混说的英文能否保留

签名 Mac 应用 `d2da535` 在 M5 上以正常语速走 AppKit 实际文字与 SQLite 归档。A 是原始 Qwen 0.6B，B 在该版本的 `native/LocalASR/Sources/SaytileModelWorker/Worker.swift` 中仅把 `language: "Chinese"` 改为 `language: nil`。两份主程序移除签名后的 SHA-256 相同。量化权重、分块、VAD、音频和评分器均相同。没有使用私人录音。

Qwen 官方 Python 允许不指定语言。此处固定的 Swift 运行库会在两种情况下都附加转写标记，nil 只省去指定语言前缀。本次实测对象是该原生运行库。[Qwen 官方推理实现](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/qwen3_asr.py) · [固定 Swift 实现](https://github.com/soniqo/speech-swift/blob/a57702e6f523fa36ac5532d2bdc5f35f701a052c/Sources/Qwen3ASR/Qwen3ASR.swift)

| 队列 | 固定中文 | 不指定语言 |
|---|---:|---:|
| 已报告反例，英语原词精确命中 | 0 / 11 | 7 / 11 |
| 另选 4 段混说，MER 错误 / 参考单位 | 13 / 79 | 8 / 79 |
| 另选 4 段纯中文，CER 错误 / 参考字 | 0 / 103 | 0 / 103 |
| 有至少两次有效窗口更新 | 8 / 9 | 9 / 9 |
| 首次有参考词组支持的更新 P50 / P95 | 0.858 / 2.074 秒 | 1.259 / 2.648 秒 |
| 有效更新间隔 P95 | 1.288 秒 | 1.294 秒 |
| 音频文件结束到定稿 P95 | 0.244 秒 | 0.299 秒 |

原速窗口复现了 0.6B 把整句英文转为中文的故障。不指定语言时保留了英文，但漏掉句首的“就是”，也有英文错词。四条混说对照中，一条 CER 增加 1 个字符错误，一条减少 10 个，两条持平。同一反例在 1.7B 固定中文时保留了英文，也出现了错词。

除报告的反例，8 条对照在运行前按公开语料 ID 的固定哈希次序、语种和时长分层选出。样本数量有限，并有部分 ID 与以往评测重合。这一诊断不单独决定默认模型。重新构建两份对应 App 并签名后，可用 `scripts/mandarin/isolated-windows.py` 指定两份应用、已有权重和 WAV 目录、随附的 `samples.json` 与独立输出目录进行交错原速复测。[原始输出、程序指纹及逐条差分](results.json)
