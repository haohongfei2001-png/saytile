# 普通话评测来源与归属

- Google FLEURS，Conneau 等，普通话简体 test 分片。CC BY 4.0。分片 695,674,033 字节，SHA-256 `87c0aebbe183f3a36ac87b5c3421b6ab57036824744ff695029a3f858e7622fd`。取 160 条不同原文。另选其中前 20 条，交替施加 −20 dB 音量或固定随机种子的 15 dB SNR 白噪声。清单分别标识改动。[固定版本](https://huggingface.co/datasets/google/fleurs/blob/70bb2e84b976b7e960aa89f1c648e09c59f894dd/parquet-data/cmn_hans_cn/test-00000-of-00001.parquet)
- ASCEND，CAiRE HKUST，Lovenia 等。CC BY-SA 4.0。test 分片 SHA-256 `a4c81d2b5ed6124f052089a695972808c16e0ce0c365ec9773c5d1a8fcf043a7`。按数据集标签各选 80 段普通话和 80 段中英混说。此处发布的 ASCEND 原文与相关改编继续适用 CC BY-SA 4.0。[固定版本](https://huggingface.co/datasets/CAiRE/ASCEND/blob/737e9800ae31be9932ba8464c80366559bd28424/main/test-00000-of-00001.parquet) · [署名-相同方式共享](https://creativecommons.org/licenses/by-sa/4.0/)
- AISHELL-1，Beijing Shell Shell Technology、Bu 等。OpenSLR 33 列明 Apache 2.0。取固定公开 test 转换分片首片的 100 条，分片 364,047,728 字节，SHA-256 `2466b1e851147943d4a2c46e1dddc8a70a45b733065c7f6a86e44bd88d5579c6`。其原文来自 answer 字段，行键可回溯到音频内容。[OpenSLR 来源与许可](https://openslr.org/33/) · [固定转换分片](https://huggingface.co/datasets/AudioLLMs/aishell_1_zh_test/blob/e73dc7f096ecea5c8e5c722446c8d3b4014fdd18/data/test-00000-of-00003.parquet)

发表清单包含公开参考文本、行键、版本及音频 SHA。未提交数据集音频。采样在模型输出前固定，按“语料名 + 原始行键”的 SHA 排序、剔除重复参考、限制时长 1.2 至 26 秒。AISHELL 资料包含来自不同口音地区的发音人，本次未给单条音频推断口音。低音量、加噪复本和真人轻声有不同的测试意义。
