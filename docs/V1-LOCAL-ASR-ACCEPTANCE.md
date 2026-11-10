# Saytile RC2 · 本机实时文字工程验收

**结论：在 Apple M5 上，Saytile 签名原生窗口能在讲话中持续出字。** 10 段来自公开中文语料的真人录音，以原速进入正式音频环、VAD、独立原音写盘、单一识别会话和 TextKit 时间轴。四种可边说边显示的引擎各测了 10 次。每路在所有 7 段超过 10 秒的样本中都出现了至少两次与原话相符的显示更新。三种整段模型只能为已保存的录音生成新版本。未使用个人麦克风、私人历史或收费 API。

[唯一 DMG、校验与回退](../deliverables/local-asr/README.md) · [14.94 秒真实窗口录像](../evidence/local-asr/delivery/live-panel.mp4) · [M5 逐模型测量](local-asr/M5-MEASUREMENTS.md) · [机器验收收据](../evidence/local-asr/acceptance.json)

安装包 `1.0.0-rc.2-local-asr.3`，原生源码 **e7c4ac86231090ef820178d4543db745944af4a4**；61,598,282 字节；SHA-256 `51acefcbc14e2536b4b7aaf8f8e0ad13a081d272ebe2a136f4e977c9ce9ad57f`。DMG、App 和原生助手均经签名。Gatekeeper 返回 **rejected / Unnotarized Developer ID**，因此公开分发 BLOCKED。GitHub 只交付在 [Draft PR #15](https://github.com/haohongfei2001-png/saytile/pull/15)，未替换已发布产品。

## 在面板上看到了什么

从持续声学起点至屏幕上第一段非标点文字的秒数（每路 10 段，最近秩分位数）。第二组数据要求文字包含参考原话中至少两个相邻字符，用来揭示无关的开头词。它是参照判据，不能证明开头每个字都对。

| 本机路径 | 能力 | 首次可见 P50 / P95 | 首个参考双字 P50 / P95 | 连续更新间隔 P50 | 最终档案 CER |
|---|---|---:|---:|---:|---:|
| Apple SpeechAnalyzer | 真流式 | 0.85 / 1.92 s | 1.29 / 2.07 s | 0.15 s | 12.14% |
| sherpa Streaming Paraformer INT8 | 真流式 | 0.80 / 1.16 s | 1.08 / 1.43 s | 0.59 s | 12.40% |
| NVIDIA Nemotron 3.5 0.6B / Metal 8-bit | 真流式 | 0.68 / 1.20 s | 0.98 / 1.52 s | 0.33 s | 20.05% |
| Qwen3-ASR 0.6B / MLX 4-bit | 1.2 s 分块重解码 | 0.81 / 3.54 s | 1.16 / 3.65 s | 1.22 s | 8.97% |

这里的 CER 用用户最终能取用的档案文字统计。直接向识别器逐文件喂入相同音频时，CER 分别为 10.29%、15.04%、20.32%、8.71%。VAD 分段、上下文与文件边缘会影响真实档案。两个结果都保留，不能拿工作进程的成绩替代产品表现。面板记录包含启动/调度开销；部分测试与另一隔离的轻量录音会话同时运行。样本少、语料为普通话朗读；不推及所有环境、口音、语言或机器。

**模型取舍。** 自动推荐 Apple 中文：这批样本上有连续而密的真实增量、适中的错误率，不需要再下载第三方模型。轻量选择 sherpa：约 237 MB 权重、出字间隔稳定；当 Apple 中文资源未准备且 sherpa 已安装时可自动选它。希望准确率优先、能接受尾部反复变化的用户可手动选 Qwen 0.6B；它没有达到首字 P95 的工程目标。Nemotron 是可验证的原生 Metal 流式适配器，但中文错误更多，不进入中文默认名单。

仅重识别时，SenseVoice Small 的逐文件 CER 最低（31/379，8.18%）；与 Qwen 0.6B 只差两个字符。保留为质量实验，商业发行前需审查原权重许可。FluidAudio Paraformer Large 为 33/379（8.71%），目前没有显示出优于 Qwen 0.6B 的准确率，不列入常规推荐。Qwen 1.7B 为 34/379（8.97%），需要 2.23 GB 权重，此批没有精度优势。**建议正式目录优先移除 1.7B、重复的 Large 整段项，以及缺乏中文收益的 Nemotron 实验入口；开发候选保留全部手动适配器。** 没有任一模型解决这批样本里的所有人名和单位问题。

另外把十段按原速串成一条真实录音，再从相同的原音、数据库副本逐条执行三种正式档案操作。VAD 形成了 11 条记录，其中一条 1.86 秒，PCM 均方根为 −66.47 dBFS。Paraformer 和 Qwen 1.7B 对该段没有文字但保留了音频；SenseVoice 返回孤立的“i”，参考没有这个字。三者都能继续处理后续记录。将档案按时间拼回，CER 分别为 34/379（8.97%）、37/379（9.76%）和 31/379（8.18%）。**“所有 VAD 行都有正确文字”没有通过**，不能以 SenseVoice 的 11 个非空结果判断它在极安静输入上更可靠。[三路逐条实测](../evidence/local-asr/candidate-batch-cohort) · [单文件测试入口在空结果上的失败记录](../evidence/local-asr/regressions/batch-probe-empty-segment.json)

## 两个实际复现的显示故障

1. 原生助手返回短行时，父进程的读取一直等到更多字节甚至 EOF。改为按管道实际到达的字节读取、组装一条完整事件。回归要求助手仍在运行时就收到短答复。四路引擎的签名面板记录都显示了 EOS 前的多次更新。
2. Qwen 把“二十九”改成“29”后，已读保护曾从 5.03 秒一直拒绝更新到 17.10 秒。现在仅当连续两次模型输出对有限预览尾部达成一致、且保留了原来的词片段时，才重新接入同一条流。没有拼接或重写模型文字；Qwen 临时结果的外派稳定长度仍为零。[修复前](../evidence/local-asr/regressions/qwen-reading-freeze-b8d622c.json)与[修复后同一音频](../evidence/local-asr/candidate-panels/qwen-small-fleurs-zh-4719524538529342597.json)显示 8.66、9.94、11.20 秒均继续出字。大幅改写仍会被压住；该批最久的有效音频内间隔约 4.66 秒。这是它尚不适合作正式实时默认的另一个原因。

## 原音、设置和云端边界

- PCM 独立写盘后才送识别器。模型校验失败的实测中，识别进程没有启动、没有第二路 ASR，SQLite 保留失败状态以及可逐帧读取的 WAV。用户能重新准备模型后对档案重识别。[故障与待机实测](../evidence/local-asr/delivery/idle-fault.json)
- 同一段说到第 5 秒、已有文字后把模型从 sherpa 改为 Nemotron。用生产工厂和已安装的两个签名助手，确认前后两段仅记录各自一个模型。45 秒静音时助手退出，下一次讲话重新加载。[切换收据](../evidence/local-asr/delivery/model-switch.json)
- 临时显示与外部输入分开。Apple 采用系统确认边界，Nemotron 只确认已追加的共同 token 前缀；sherpa 和分块 Qwen 从不把暂定尾部作为稳定派发文本。外部输入沿用 UTF-16 增量、目标所有权和不自动发送规则。
- 自带 API 与 Saytile Cloud 模式保留。新本机录音只有在用户显式允许并提供自带凭据时，才可把该段的文字送给 GPT-6；离线可继续工作，授权不回填旧录音。识别不等待该复核，外派前缀和用户编辑不能靠它重写。真实付费端点本轮 **NOT_RUN**。本地协议和失败回归不冒充真实云连接。
- [安装包内的原生设置](../evidence/local-asr/delivery/settings-native.png)保留“本机 / Saytile Cloud / 自带 API”与“自动推荐 / 手动选择”。面板沿用批准的白色浅玻璃、单正文和原有两处控制。录像是 ScreenCaptureKit 仅捕获此次隔离进程的一个窗口，视频轨 1、音轨 0，没有后期模拟出字。[实录第六秒](../evidence/local-asr/delivery/movie-frame-6s.png)；不同背景下的材质和长期主观体验未在本轮取得新的视觉批准。
- 官方包的应用标识不变；升级与同 schema 回退保留两条合成时间轴、两份原音、编辑稿、云端授权、随机测试 Keychain 条目及 237,202,501 字节原模型，哈希逐项相同。[实测收据](../evidence/local-asr/delivery/upgrade-final.json)

## 证据与限制

- [完整 Xcode CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42732367841)：安装包源码 411/411 项 Swift Testing、50 个 suite、104 项 AppModel；52 个本地协议场景零协议违反。采集、时间轴分页、选区、原处修订、复制与外派安全继续使用已有的回归。未在用户的真实目标窗口插入文字。
- [七路原始识别输出](../evidence/local-asr/candidate-engines)、[四路真实窗口逐帧文字](../evidence/local-asr/candidate-panels)、[三路单文件实际档案](../evidence/local-asr/candidate-archive)、[逐项 CER 和错误](../evidence/local-asr/quality.json)；不分发音频样本本体。模型、编译运行时和许可见[第三方来源](../THIRD_PARTY_NOTICES.md)，每个下载文件的固定 revision、大小和 SHA-256 见[安装清单](../Sources/SaytileKit/Resources/LocalASR)。
- 识别复测使用 [Google FLEURS](https://huggingface.co/datasets/google/fleurs) CC BY 4.0、普通话 test 分片。分片和每个 WAV 的哈希见[固定来源](../research/asr-2026-11-06/corpus/sources.json)和[逐样本记录](../evidence/local-asr/candidate-engines/sherpa.json)。音频按原速注入正式麦克风环形缓冲的入口，覆盖其后的全部处理；不证明不同麦克风、嘈杂房间、睡眠恢复和实际人在场的体感。
- 可在包内源码上复建：`scripts/package-rc2-timeline-integration.sh`，使用已有 Developer ID；安装包内无 Python 或开发工具依赖。在独立数据目录挂载/复制后，`scripts/measure-local-bundle.py`、`scripts/test-local-panels.py` 和 `scripts/score-local-asr.py` 可用固定授权语料复算。所有操作由工程完成，无需用户参与测试。
