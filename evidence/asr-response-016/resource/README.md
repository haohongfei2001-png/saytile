# 484 / 486 资源实测及固定 PCM 归因

只读公开语料测试。这里保存四组原速 App+helper 原始过程计时、采样、原生收据，以及一组严格固定解码边界的 helper 控制。所有数字均绑定包内产品 SHA 和 helper SHA。没有把两个进程各自的 CPU 中位数相加。

## 原速 38.8 秒：A → B → A → B

| 顺序 | App CPU 秒 | helper CPU 秒 | 总 CPU 秒 | 同时 physical footprint 峰值 MiB |
|---|---:|---:|---:|---:|
| 1：484 | 2.41 | 9.75 | 12.16 | 1687.9 |
| 2：486 | 2.46 | 9.83 | 12.29 | 1815.2 |
| 3：484 | 2.29 | 10.53 | 12.82 | 1673.7 |
| 4：486 | 2.46 | 9.57 | 12.03 | 1800.8 |

**CPU 改善不成立：两轮区间重叠，不能宣称已降低识别总 CPU。** 各进程累计 CPU 以 200 毫秒采样，进程若在采样间退出，计数是下界。原速内存峰值中 486 比 484 约高 127 MiB；增量集中在 worker，App 约 25–26 MiB。

`native-cpu/`保留每组 `process.json`的全部采样、对应完整 raw worker/publication/window 收据及运行日志。`memory-attribution.json`记录峰值时刻、加载/预览/EOS 阶段和帧数。process-launch 与 probe-start 没有精确共同时间桥，峰值邻近 decode 标注为近似，不能据此伪造精确分配调用栈。

## 相同解码边界控制

为区分产品变化与动态积压改变的音频窗口/解码形状，采用已有 `QwenWorkerFinal.py` 的 framing 协议，固定 16 个 partial 输入边界；每次真实输出返回后才发送下一包。相同公开音频前 481280 帧（30.08 秒）最后独立 EOS。所有单包不超过 65536 字节，没有强制补 PCM、盲重试或虚构输出。

- 16 个 partial、ready 和 EOS 的帧数、顺序及文字两版完全一致，PASS。
- helper 全程峰值：484 **1798.986 MiB**，486 **1798.423 MiB**。两者都在同样的 EOS 阶段达到峰值，固定额外 127 MiB 的全程峰差未复现。
- helper CPU **3.20 / 3.19 秒**。这不是原速体验测试，单对结果不能证明 CPU 改善。
- **阶段内存差异仍未归因**：候选若干中间 preview 的 footprint 仍比基线高 88–417 MiB，后段趋同。不能因为全程峰相同就宣称内存问题已解决，也不能唯一归因为帧边界。25 毫秒控制采样与原速 200 毫秒采样不同，只能在各自同条件组内比较。

`fixed-pcm/`保存完整控制脚本、所选边界的旧实际输出来源、两次逐阶段采样、raw events、stderr、逐次比较和明确保留限制的 `RESOURCE-ATTRIBUTION.json`。

## 源码与构建溯源

当前旧缓存、新 vendor、固定 upstream 的 Qwen `WeightLoading.swift`、`QuantizedTextDecoder.swift`及 MLXCommon/SpeechVAD 权重加载器 SHA 相同。新旧五个 SPM checkout 均干净且匹配同一锁定 revision。详见 `vendor-hash-comparison.json`、`dependency-provenance.json`。

484 helper `9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e` 与 476 正式交付/安装收据完全相同，不是已拒绝的 EOS 或启动实验 helper。历史收据及其 Git 路径、commit、原始 JSON 哈希均保存在 `memory-attribution.json`。当前缓存哈希只能说明检查时状态，不能重建过去所有未记录构建步骤。

仍未取得 allocator 调用级根因，不能把资源优化宣布完成。24 GB M5 结果不代表 8 GB Mac 已验收；整机功耗、GPU/ANE 资源、电池及用户麦克风均 NOT_RUN。

`COPY-SOURCES.json`保留复制来源；`SHA256SUMS.txt`覆盖本目录除校验表自身外的全部文件。无模型权重、可执行包或私人音频。
