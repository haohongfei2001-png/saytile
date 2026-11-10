# 复现普通话对照

在工程根目录运行。安装包和消费者电脑均不需要 Python。评测使用 Python、numpy、soundfile 与 pyarrow 准备公开语料，原生识别走 Swift、系统 Speech、ONNX 或 MLX。参考文本的版权与授权见 [语料清单](../../evidence/mandarin/SOURCES.md)。

1. 将该清单中三个固定版本的 Parquet 下载到评测目录。运行 `python3 scripts/mandarin/corpus.py paired /path/to/fleurs-zh.parquet` 和 `python3 scripts/mandarin/corpus.py aishell`。ASCEND 与 AISHELL 文件应放在 `.build/mandarin/asc.parquet` 和 `.build/mandarin/air.parquet`。脚本核对整片 SHA-256，再按固定规则导出 16 kHz WAV。发布的清单记录每条音频哈希。
2. 按工程的本地运行时说明构建并签名。将安装候选放在独立目录，按仓库模型清单校验权重，权重根目录使用 `.build/local-asr/weights`。Zipformer 的测试使用本地已核对的研究副本。
3. 运行 `scripts/mandarin/build-probe.sh`。将 `SAYTILE_BENCH_APP` 设为安装的 App 的绝对路径，将 `SAYTILE_BENCH_RESULTS` 设为新的空输出目录的绝对路径。为四个模型 apple、sherpa、qwen-small、zipformer 及两个子集 paired、aishell 分别运行 `scripts/mandarin/run-cohort.sh MODEL COHORT`。每个录音使用单一模型。direct 从完整音频建立一个识别会话，product 经过采集转换、VAD、独立 journal、识别、SQLite 及版本管理。加速喂入只产生质量收据。
4. 原速文字帧用 `scripts/test-local-panels.py`，指定安装的 App、权重、WAV、固定 panel-cohort.json 以及输出目录。每项都是新进程与独立数据库，通过已排版的 NSTextView 观察用户可见文字。原速输入使用产品录音环。初次显示、修订、原音和最终档案均不依赖云端。
5. `scripts/mandarin/quantization.py --help` 给出同一原生 CTC 助手运行 FP32 和 INT8 文件的参数。性能采样用 `power.py`，相邻空闲与运行各保留原始数据。半小时完整性测试用 `soak.py`。重新统计用 `python3 scripts/mandarin/score.py --sha PRODUCT_SHA --wav .build/mandarin/wav --results evidence/mandarin/final`。
