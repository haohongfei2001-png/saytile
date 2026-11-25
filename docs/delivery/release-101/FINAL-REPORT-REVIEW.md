# 1.0.1 完整原速报告与原生结果独立复核

本次仅增加报告脚本与合成数据回归，不修改产品，不启动 ASR、浏览器或用户 App。完整 440 段正在执行时不评分残缺集，不改动主工作树的原始证据。

## 完整 420+20 原速对照

新增 `scripts/mandarin/report-realtime-cohort.py`，复用既有 `score-local-asr.py` 的 `rating`、`pooled`、`quant`。不改 CER 规范，不替换数字，不排除空定稿或失败记录。

执行前必须同时满足：两臂进程均成功结束；每臂恰好 440 个唯一、有序 ID；固定清单 SHA；160 FLEURS、80 ASCEND 中文、80 ASCEND 混说、100 AISHELL 原始样本，以及另行统计的 10 quiet + 10 noise15db。衍生语料不在清单最后，**不能用 `[:420]` 分组**。

脚本逐项校验实际 WAV SHA、PCM 格式/帧数、清单时长、结果帧数/时长，以及 `qwen-small / product / realtime` 路由。空模型执行、空文字和失败状态保留在分母和问题清单中；不允许混入其他 ASR。喂入耗时只允许现有夹具声明的 1 ms 时钟容差，迟到喂入仍完整计分并单列分布。开始前快照输入摘要，结束前确认未发生写入变化。

以下命令仅由主负责人在两个 440 集合完整后执行，且输出文件不得覆盖既有收据：

```sh
python3 scripts/mandarin/report-realtime-cohort.py \
  --root evidence/release-101/regression-final \
  --manifest evidence/release-101/setup/input440.json \
  --manifest-sha256 f275794d4a14d8e8dae5732deda2f50d5653583a32be27c921d66ac9b0e753c8 \
  --audio /private/tmp/saytile-beta-021-20261123/.build/mandarin/wav \
  --out evidence/release-101/regression-final/quality-comparison-complete.json
```

必须保留的证据边界：

- 440 JSONL 未记录首字、候选更新、AppKit 可见时间或 CPU/内存；这些字段输出 `NOT_RECORDED`，不能填 0 或借用 16 段数字。
- `settledAfterFeedSeconds` 包含队列等待及数据库读回，是喂入结束至档案收敛时间，不能冒充模型原始 EOS 延迟。
- 原始 JSONL 和 setup 构建收据未嵌入产品源码 SHA。报告验证实际 CLI 与 fixture 的 SHA，产品源码关系必须由独立构建/链接等价性收据提供，并明确是事后核对。
- 该夹具直接选择 qwen-small，不是 AppModel 自动推荐路由验收。原生 16 对另有 `automatic=true` 严格校验。
- 输出 `validation_status=PASS` 只表示完整且可比，不代表产品发行 READY；质量退化、空稿和状态异常均独立保留。

8 项合成 PCM 报告回归通过：完整性、空稿分母、缺行/重复/乱序、进程未结束/残行、错误路由/帧数/哈希/加速喂入、坏 WAV/清单、CLI/fixture 篡改、慢喂入保留。未运行实际 ASR。

### 事后补齐 CLI 与静态库绑定

`evidence/release-101/report-audit/cohort-link-retrospective.json` 保存两臂原 CLI、原静态库、同一 fixture 和仅重链接产物的 SHA-256、命令及时间。先从二进制 OSO 条目确认 Debug 对象路径，再以 `nice 20` 重新编译/链接这一个 fixture；未构建 Package，未运行 CLI。

两臂在仅归一化 Mach-O UUID、代码签名及签名派生的 `__LINKEDIT` 尺寸后，其余全部二进制字节相同。旧 CLI 确实对应 `release100-build/Debug/libSaytileKit.a`，新 CLI 对应 `release101-storage/Debug/libSaytileKit.a`。可运行同目录 `verify-link.py` 只读复核，不能把新产物的 SHA 改写成原测试 SHA。原 setup 收据保留。

首次 sandbox 中 `nice` 被拒绝并最终超时的记录也保留。随后通过已有构建授权在 sandbox 外重链接，仍保留 `nice 20`，没有去掉优先级参数或运行识别。完整原速语料的资源结果若受这段低优先级编译干扰，应由主负责人对照时间记录；440 夹具本身没有 CPU/首字指标，不能据此制造性能结论。

## 已完整完成的原生 16 对结果

原始收据：`evidence/release-101/regression-final/paired16/`；汇总：`native-comparison-including-failure.json`。上一版源码 `42d8e98eaf04a56d34a36cc1aca2aff7061150f4`，候选源码 `73ad857442964437929819ba9965f6bcfdcefd27`。每臂 16 条均严格对应原音 SHA、`automatic=true` 与唯一 `qwen-small`。

| 观察项 | 1.0.0 | 1.0.1 候选 |
| --- | ---: | ---: |
| 15 段最终 CER | 46/568 = 8.10% | 46/568 = 8.10% |
| 首个可见参考词 P50 / P95 | 1.031 / 1.543 s | 1.052 / 2.126 s |
| 有效可见更新间隔 P50 / P95 | 0.345 / 0.977 s | 0.289 / 1.007 s |
| 喂入结束至收敛 P50 / P95 | 0.247 / 1.952 s | 0.290 / 1.701 s |
| 预览 A→B→A | 2 | 0 |
| 15 段合计 App + worker CPU | 57.19 s | 55.42 s |
| 15 段峰值同步 footprint | 1512.27 MiB | 1541.22 MiB |
| 38.8 s 长句最长可见有效更新间隔 | 2.405 s | 3.085 s |
| 38.8 s 长句 worker 最长有效更新间隔 | 2.031 s | 3.082 s |
| 38.8 s 长句喂入结束至收敛 | 0.768 s | 0.982 s |

**PASS 范围：** 16/16 最终文字和记录状态逐项一致；所有记录 completed；15/15 在音频结束前出现有效参考词；两臂窗口末帧全部与档案相同；无失败 invocation 或 surface blocker。38.8 s 长句单列 CER 为 31/205，两臂相同，不混入 15 段分母。

**必须披露的风险：** 不能宣称本轮实时性全面不退化。候选首字 P95 的最大值来自 `ascend-mixed-7c8bdcb41bb98a40`（2.126 s）。候选另一个普通样本 `ascend-mixed-ff9c42612780330b` 的最长显示间隔为 2.195 s。38.8 s 长句约 30.74–33.83 s 发生 3.085 s 可见停顿；对应 worker 约 30.70–33.79 s 无新的有效输出，不能归因于 UI 刷新，也不能声称“发布器已经解决长尾”。单轮交错对照不足以证明 CPU 下降或延迟变化的因果关系。

以上是公开 PCM 在真实原生窗口中的结果，不是现场麦克风或用户口音验收。原始报告首次漏传 `--automatic` 的断言失败和修正记录均保留；修正仅是让报告要求与实际自动路由一致，没有删除断言或重跑音频。
