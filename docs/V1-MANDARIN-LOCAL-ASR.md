# 本地普通话识别 · M5 原生候选

本文记录源码 `a55d51a` 的历史实测。内测 0.13（414）更换了本机中文默认引擎，安装基线、最新四模型实测与原速窗口见[本轮交付记录](../evidence/mandarin-quality-20261114/README.md)。

产品源码 `a55d51a1ff4711340bc63ea5c8ecd927dd2327d3`。四种引擎均已在 Apple M5、24 GiB、macOS 27 的签名原生窗口实际运行。屏幕文字由当次唯一的 ASR 生成，采集和原音写盘独立于识别。Zipformer 为研究候选，正式目录提供 Apple、Streaming Paraformer 与 Qwen 0.6B。云端模式保持原有授权路径。

**安装包** 为 61,646,743 字节。Developer ID 签名和升级演练通过，Gatekeeper 对此未公证构建返回拒绝。[DMG 与安装说明](../deliverables/mandarin-local/) · [原生窗口实录](../evidence/mandarin/delivery/zipformer-window.mp4) · [产品源码及权重指纹](../evidence/mandarin/delivery/build-receipt.json)

## 评测方法

统一评估 420 个不同参考的公开人声样本，另含 20 次同源扰动。所有模型共享 16 kHz 单声道音频、量化文件哈希、参考文本及规则。参与评测的第三方权重按需加载。公布的原始 JSONL 可逐句追溯。CER 使用仓库 NFKC、casefold、数字内标点保留以及逐字符最短编辑距离。没有繁简、数字或术语同义替换，空结果按全句漏字计算。中英混说另计中文逐字、英文逐词 MER。数字、否定词、金额、时间、术语的字面保留次数在机器结果中逐类给出，等价读法需要单独判断。[来源与授权](../evidence/mandarin/SOURCES.md) · [复现步骤](../scripts/mandarin/README.md)

模型直通结果来自实际量化模型的完整音频会话。产品档案结果经过采样转换、VAD、PCMJournal、唯一 ASR、融合发布和 SQLite。两类批量回放为了取得质量使用加速喂入。首次显示、修订与定稿耗时取自另外 15 条原速、每条冷启动的签名 AppKit 窗口。这 15 条分布在朗读、自然普通话及中英混说，每路各有 5 条达到 10 秒。首字取 −55 dBFS 持续声起点后的非标点文本。有效更新要求本帧引入参考中出现的相邻双字。P95 使用最近秩，因此 15 条中的 P95 是本次最大值。活动区间的末端用实际音频能量估算，EOS 延迟以播放完文件到识别任务排空计。[窗口原始观测](../evidence/mandarin/delivery/panels/)

## 公开成绩与具体权重

icefall 的中文 Large CTC greedy streaming 报告 AISHELL-1 dev/test 为 1.71% / 1.97%，WenetSpeech net/meeting 为 10.62% / 8.13%。所指原始 checkpoint 的流式 CTC 评分文件名包含 epoch-999、avg-1、chunk-32、left-context-256。模型用 FP16 训练选项，论文/配方表的成绩不代表部署版 INT8。发布的 INT8 ONNX 单文件为 162,290,887 字节，即 154.77 MiB，含词表共 162,311,515 字节。字节、转换版本与 SHA-256 均在清单内。sherpa-onnx v2.0.1 使用 Apache 2.0，ONNX Runtime 使用 MIT。维护者说明转换权重跟随原 checkpoint，并在回复中举了 XL 的例子。这里使用的 Large checkpoint 和转换仓库没有可核实的权重商用授权。[icefall 配方](https://github.com/k2-fsa/icefall/blob/master/egs/multi_zh-hans/ASR/RESULTS.md) · [sherpa 官方模型说明](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-ctc/zipformer-ctc-models.html) · [维护者说明](https://github.com/k2-fsa/sherpa-onnx/issues/3918#issuecomment-5754861224) · [固定权重记录](../evidence/mandarin/zipformer-provenance.json)

Qwen 团队模型卡在其公开评测表列出原始 0.6B 的 FLEURS-zh 2.88%、AISHELL-2-test 3.15%、WenetSpeech net/meeting 5.97% / 6.88%。本产品使用独立转换的 4-bit MLX 权重，FLEURS 子集与本地打分均不同。Apple 的本次系统资产和 sherpa 双语 Paraformer 的精确 INT8 转换缺少可直接配对的官方同口径分数。两者的本机结果与其他模型采用相同评分程序。[Qwen 模型卡](https://huggingface.co/Qwen/Qwen3-ASR-0.6B#evaluation) · [Paraformer 实际权重](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/tree/8e40c43232a1c5c66c82111efc5820d3accca11b)

FP32 和 INT8 转换在同一台 Mac 上使用相同的原生 sherpa CTC 助手、CPU、两线程、贪心解码、200 ms PCM、一致的末尾补齐与 token 表。AISHELL 子集共有 1,465 个参考字符，FP32 错 53 字（3.62%），INT8 错 50 字（3.41%）。100 段中量化后 4 段改善、1 段变差、95 段错误数持平。按语料分层的其他差异和两个精度的逐条输出已归档。[量化对照](../evidence/mandarin/quantization/)


## 同音频实测

各格为“模型直通 / 产品档案”微平均 CER。前四列包含 420 段独立人声。后两列为同源扰动。不将其当作独立发音人或额外新句参与综合推荐。

| 模型 | AISHELL-1（100） | FLEURS（160） | 自然中文（80） | 中英混说（80） | 低音量（10） | 加噪（10） |
|---|---:|---:|---:|---:|---:|---:|
| Apple SpeechAnalyzer | 11.26% / 11.33% | 10.37% / 10.46% | 6.64% / 6.64% | 17.52% / 17.52% | 13.15% / 12.90% | 10.53% / 10.80% |
| Streaming Paraformer INT8 | 6.96% / 7.03% | 13.98% / 20.22% | 9.64% / 9.64% | 19.66% / 19.71% | 12.65% / 13.15% | 14.13% / 23.55% |
| Qwen 0.6B MLX 4-bit | 3.89% / 3.96% | 9.54% / 16.61% | 10.06% / 10.06% | 17.61% / 17.61% | 10.67% / 10.67% | 6.65% / 19.67% |
| Streaming Zipformer CTC INT8 | 3.41% / 3.41% | 12.36% / 19.95% | 8.35% / 8.35% | 44.91% / 44.91% | 14.64% / 14.64% | 13.02% / 22.71% |

FLEURS 的完整音频直通优于经过 VAD 分段的产品档案，实际产品取舍采用右侧档案数字。中英混说的纯中文 CTC 尤其容易损失英文名。例如在 ASCEND 的同一条公开原文中，Zipformer 将 “Houston Rockets” 写成 “HSTRK”，Qwen 写成 “Houston Rockies”。两个结果都留下了含义错误。源文本、系统输出和空结果全部保留。[归档原始输出](../evidence/mandarin/delivery/runs/) · [逐类错误与混说 MER](../evidence/mandarin/delivery/comparison.json)

420 段独立人声共 10,663 个参考字符。同一份档案按字符合并的结果为 Apple 11.57%、Paraformer 17.39%、Qwen 14.49%、Zipformer 21.35%。该加权数受语料构成影响。自然中英混说另按 MER 计为 Apple 19.55%、Paraformer 18.95%、Qwen 16.98%、Zipformer 31.82%。420 段中，四路完全空白的档案分别有 0、5、1、5 条，全部计入错误。批量回放共享机器并加速输入，调度会影响 VAD 后识别排队。另取相同 15 条在独占、原速签名窗口读库，档案 CER 分别为 12.68%、14.09%、9.68%、26.06%。这两组试次有独立分母。

## 实际窗口与确认时间

表内时间为秒。首字允许单个模型产生的真实字符。有效首显及更新要求新增参考双字。停显列计每段讲话中间及首尾的最大有效更新空档，再取 15 段的 P95。回撤次数按规范化显示文本发生前缀回改累计。

| 模型 | 首字 P50 / P95 | 有效首显 P50 / P95 | 有效更新间隔 P50 / P95 | 停显 P95 | 回撤 | 文件 EOS 至落定 P50 / P95 |
|---|---:|---:|---:|---:|---:|---:|
| Apple SpeechAnalyzer | 1.13 / 1.40 | 1.26 / 2.02 | 0.81 / 0.99 | 2.02 | 5 | 0.07 / 0.14 |
| Streaming Paraformer INT8 | 0.71 / 1.22 | 1.22 / 1.74 | 0.59 / 1.22 | 1.81 | 2 | 0.06 / 0.13 |
| Qwen 0.6B MLX 4-bit | 0.88 / 0.97 | 1.21 / 2.40 | 1.20 / 1.64 | 5.33 | 25 | 0.18 / 0.35 |
| Streaming Zipformer CTC INT8 | 0.70 / 1.13 | 0.92 / 1.38 | 0.33 / 0.92 | 3.17 | 0 | 0.08 / 0.12 |

同一识别实现的 .5 另测了长句。15 条固定短窗以外，5 条公开语音还组成了 38.8 秒的连续回放，跨越 Qwen 的 24 秒内部窗口。Apple、Paraformer、Qwen、Zipformer 的原生文字分别变化 63、65、30、104 次，档案保留两个自然时间段。这是经过剪接的真实语音压力项。[连续片段清单](../evidence/mandarin/continuous.json) · [同一原生窗口的逐帧观测](../evidence/mandarin/final/continuous/)

Qwen 同机独占 A/B 中，.3 与 .4 每条交替启动。首字 P50 从 1.21 降为 0.92 秒，P95 从 1.39 降为 1.07 秒。同一批 .5 再测为 0.88 / 0.97 秒。15 条的原速档案 CER 从 12.85% 降到 9.68%。.5 有效更新间隔 P95 从旧版 2.39 秒降到 1.65 秒，同时累计回撤从 22 增至 25 次，一条中英混说的有效更新空档从整体旧版最坏 3.93 秒扩大至 5.33 秒。首字改善后仍有长尾。Qwen 使用分块重解码，临时尾部不进入外派稳定前缀。[基线及候选 A/B](../evidence/mandarin/qwen-windows-ab.json)

## 内存和能耗

M5、24 GiB，接交流电，电量显示 100%。每次重新启动 App，播放同一条公开语音，按约 0.35 至 0.7 秒采样进程，按 1 秒采样 IOReport。下表保留 .5 两次冷启动中较高的 App 与助手瞬时合计物理占用，以及第二次隔离测试的整机空闲和活动均值。MiB 为 2²⁰ 字节。Apple 的模型由系统管理，公开接口不提供可单独核对的资产字节数。

| 模型 | 第三方磁盘 MB | App / 助手各自峰值 MiB | 同时峰值 MiB | 整机 W 空闲 → 活动 | CPU / GPU / ANE 活动 W |
|---|---:|---:|---:|---:|---:|
| Apple | 系统管理 | 37 / 0 | 37 | 12.42 → 13.99 | 2.10 / 0.11 / 0.00 |
| Paraformer | 237.2 | 37 / 472 | 509 | 14.25 → 13.54 | 2.24 / 0.07 / 0.00 |
| Qwen 0.6B | 712.8 | 36 / 1407 | 1442 | 12.76 → 17.11 | 3.35 / 0.90 / 0.00 |
| Zipformer | 162.3 | 38 / 398 | 436 | 12.30 → 14.08 | 2.39 / 0.12 / 0.00 |

Qwen 的第二次隔离运行同时峰值约 897 MiB，第一次达到 1,442 MiB（1.51 GB）。单独助手最高约 1,407 MiB。最大值用于内存决策。从 .5 起，将模型 SHA 校验的每次读取限定在独立 autoreleasepool，限制已有 MLX 分配器的空闲缓存。相同输入下，修复前 App 约 716 MiB，修复后约 36 MiB。Qwen 在 AISHELL-1 的档案准确率、混说 MER 和较短的首字延迟支持手动选择。按消费级资源目标保留 Apple 为默认。

可读取的 localspeechrecognition、corespeechd、corespeechd_system、aneuserd 等服务采样独立列在 JSON。系统服务有共享及访问边界，无法完整归属到单一 App。CPU/GPU 活跃度、组件功率、进程 CPU、RSS、物理占用、系统内存压力与 swap 起止均保留。整机负载会波动，某些试次的空闲功率高于活动功率，不能由此推断耗电倒挂。电池续航、单 App 的精确 ANE 占用、真实 8 GB 内存压力项目仍待对应硬件和接口。[第一组进程采样](../evidence/mandarin/final/resource/) · [独占系统遥测与服务采样](../evidence/mandarin/final/isolated-power/)

.6 在相同设备上重新进行了四路独立采样。App 与助手同时峰值分别为 Apple 35 MiB、Paraformer 509 MiB、Qwen 959 MiB、Zipformer 431 MiB。建议仍参考此前测到的较高峰值。两版下载器不同，语音助手的机器指令、常量和模型清单通过逐项比对。[.6 资源收据](../evidence/mandarin/delivery/resource/) · [原生二进制比对](../evidence/mandarin/delivery/inference-parity.json)

## 产品裁决

- **默认保留 Apple。** 420 段独立语音的同条件档案微平均 CER 为 11.57%。朗读和自然普通话的整体组合比其他在测本地路径更稳，系统资产准备好即可使用。
- **轻量备选为 Streaming Paraformer。** 已装权重共 237.2 MB。M5 的首字 P50 为 0.71 秒，15 条窗口测试累计出现 2 次前缀回改。系统中文资源未安装且 Paraformer 已就绪时，自动选择已有轻量模型。
- **Qwen 0.6B 保留手动选择。** AISHELL-1 档案 CER 为 3.96%，中英混说的逐词/逐字 MER 为 16.98%。分块结果具有实际应用价值，长尾、回撤及冷启动峰值是它的代价。持续重载压力下确实出现过识别取消，失败原音保留。
- **Zipformer 维持研究状态。** M5 上可以真流式出字，模型文件小，AISHELL-1 档案 CER 为 3.41%，但中英混说档案 CER 为 44.91%。其权重商用许可有待核实。普通设置不提供下载入口。

## 机器验收

- **PASS** — 四路真实离线识别、签名窗口原速出字，所有模型的 5/5 段十秒以上样本都有多次有效更新。SQLite 档案、同一模型的单一输出、截图和独立窗口录屏均有原始证据。全流程没有调用第三方 ASR API。[隔离原生窗口录屏](../evidence/mandarin/delivery/zipformer-window.mp4)
- **PASS** — Xcode CI 411 个 Swift 测试、104 项 AppModel 检查与原生目标输入保护。12,000 条历史的原生滚动、选区、复制与分页在本机和 CI 均通过。早先一次 CI 的历史选区断言失败已记录，修订测试选择的是屏幕上已可见的历史行，保留全部原判据。[源码 CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42847955651) · [本机时间轴收据](../evidence/mandarin/delivery/install/timeline.json)
- **PASS** — 只读 DMG 安装，Developer ID 签名、Hardened Runtime、v5 → v6、历史原音、编辑稿、隔离 Keychain canary、旧数据库拒绝降级及备份回退。损坏模型不会启用，原音保持可用。Zipformer 在长静音后释放，下一句话重新加载。暂停下载、真实远程续传、完整哈希、离线复用和删除已验证。[安装与回退](../evidence/mandarin/delivery/install/) · [故障注入](../evidence/mandarin/delivery/zipformer-fault.json) · [下载器收据](../evidence/mandarin/delivery/suffix-download.json)
- **PASS** — 在 .5 的半小时测试中，Zipformer 以原速运行 1,803 秒。102/102 段完成、音文可读、时间轴顺序与数据库完整，无外部派发，原生显示变化 4,836 次。[半小时收据](../evidence/mandarin/final/soak-zipformer.json)
- **FAIL** — 在 .5 的半小时测试中，Qwen 与其他独立工程基准共用机器时，半小时的 102 段中有一段识别取消。101 段完成，全部 102 段原音可用。屏幕探针退出码为 0，逐条读库发现了这次失败。[全部状态和原始错误](../evidence/mandarin/final/soak-qwen-small.counts.json)
- **PASS** — Qwen 在同一音频和已核对相同的识别实现上独占识别负载复测 1,803 秒，102/102 段完成，原音和索引逐条核对通过，原生窗口更新 1,054 次。[独占复测](../evidence/mandarin/final/soak-qwen-solo.json)
- **PASS** — .6 下载器从空目录处理受控 HTTP 206 分段和 HTTP 200 完整正文，两个分支均对 162,311,515 字节执行最终哈希。Content-Range 与请求范围不符的受控响应被拒绝，保留 2 MiB 连续前缀。[受控传输收据](../evidence/mandarin/delivery/controlled-transfer.log)
- **PASS** — 同一源码在独立 macOS 26 CI 从空目录通过公开 CDN 下载、暂停、续传、全量 SHA 校验、重新打开模型库及删除。Paraformer 共 237,202,501 字节，用时 14.00 秒；Zipformer 162,311,515 字节，12.66 秒；Qwen 712,777,119 字节，51.41 秒。耗时包含整个测试流程。三个模型皆未触发传输错误重试。[公开下载的原始日志](../evidence/mandarin/delivery/public-download-ci.log) · [独立 macOS 作业](https://github.com/haohongfei2001-png/saytile/actions/runs/42847941105/job/129955608488)
- **FAIL** — 本机现有代理下，.6 从空目录下载 Zipformer 和 Qwen 的测量未完成。端点返回正确 206 和实际正文，Zipformer 的日志记录到 35,651,584 字节检查点。测试到达无新连续进度的时限。可重试的前缀和已安装权重不受影响。本机的公共 CDN 完整冷安装仍待验证。[本机传输限制](../evidence/mandarin/delivery/host-cold-transfer.json)
- **BLOCKED** — Gatekeeper 返回 Unnotarized Developer ID，商业公开分发仍待公证。Zipformer 权重的商业分发授权也未确认。
- **NOT_RUN** — 真实 8 GB Mac、离电续航、按个人标注口音的细分 CER、私人麦克风对话及真实云端 GPT 核对。本轮只使用获授权的公开录音。

源码、DMG、当前机器、模型版本和执行助手的哈希见 [构建收据](../evidence/mandarin/delivery/build-receipt.json)。完整原始输出、错误分型、增量轨迹与归档质量见 [机器指标](../evidence/mandarin/delivery/comparison.json) 和 [420 段汇总与失败案例](../evidence/mandarin/delivery/quality-verdict.json)。

最终逐项状态及适用源码见[机器验收清单](../evidence/mandarin/delivery/acceptance.json)。
