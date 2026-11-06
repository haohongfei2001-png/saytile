# 单一转写配对评估接续包 · 2026-11-07

本目录只提供本地准备、完整性预检、原生导出索引与离线评分。不实现 ASR，不调用模型，不修改授权、Keychain 或生产资料。复用相邻 `quality-evaluation` 的 `metrics.py`、`evaluate.py`、参考标注加载器及配置模板；冻结原有 24 ID，不重新采样。

| 配置 | 实际工程候选 | 原生探针模式 |
|---|---|---|
| A | Qwen Message 中文专家 + GPT-6 Astra | single-expert-baseline |
| B | AssemblyAI 英文专家 + GPT-6 Astra | single-expert-baseline |
| C | 平等中文、英文专家 + GPT-6 Astra | multi-expert-fusion |
| D | Soniox stt-rt-v6（multilingualASR）+ GPT-6 Astra | single-expert-baseline |
| E | 中文、英文、Soniox + GPT-6 Astra | multi-expert-fusion |
| F | GPT-6 原生音频 | NOT_AVAILABLE；按本轮产品能力裁决，不生成命令 |

A–E 均只有同一 GPT 核心，`high / standard`，仅逐字证据融合。Qwen/AssemblyAI 是初始工程候选，未胜出。保留原 UUID 尾号 `0001/0002/0003/0004`，避免断开原 Keychain 身份。所有专家使用同一完整 WAV 对应的 PCM，不按参考语言路由。配置使用 `highestQuality`，无话题提示，自动恢复关闭。

已提交的 `prepared/configurations/` 全部 `cloudEnabled=false`、逐模型 `cloudConsent=false`；Qwen workspace 是占位符。准备器不会将任何授权设为 true。`commands.json` 是 120 个未执行 argv（24×5，按音频轮换配置顺序），不是执行脚本，动态 GPT 调用数仍未知。执行所需配置、Keychain、处理与费用授权由原生探针原有校验负责，本目录没有绕过入口。

## 本地命令

在仓库根目录执行。变量由父工程流程提供：`AUDIO_ROOT` 为现有冻结语料目录；`ACCESS_PREFLIGHT` 为父流程提供的最新纯元数据 JSON；`NATIVE_APP` 必须是最终候选的实际可执行文件路径；`NATIVE_SOURCE_COMMIT` 是该二进制嵌入的完整 40 位提交；`RUN_ROOT` 为本目录内新的隔离运行目录。这里不猜测原生构建位置。

```sh
EVAL=research/asr/benchmark/single-transcript-2026-11-07
python3 -B "$EVAL/harness.py" preflight \
  --audio-root "$AUDIO_ROOT" --access-preflight "$ACCESS_PREFLIGHT" \
  --output "$RUN_ROOT/preflight.json"
python3 -B "$EVAL/harness.py" prepare --app "$NATIVE_APP" --outdir "$RUN_ROOT"
python3 -B "$EVAL/harness.py" score --summary-only --output "$RUN_ROOT/not-run.json"
python3 -B -m unittest discover -s "$EVAL" -p 'test_*.py' -v
```

以上命令只做本地工作，当前即可运行。`preflight` 同时输出文件/PCM 哈希与尺寸明细；参考文字只由评分器读取，不写入原生调用配置或 argv。准备器对已有不同内容拒绝覆盖。

**本轮云执行被阻断，不运行下一条命令。** 以下是未来已有独立授权且原生候选就绪时的工程接口示例；无需终端用户测试。选择一个 `CONFIG_ID` 和冻结 `FIXTURE_ID`，使用空的独立资料目录，保留原生退出状态及日志；不要自动重试未知结果。A/B/D 要带下列单专家参数，C/E 则省略该参数：

```sh
"$NATIVE_APP" --multi-asr-probe "$AUDIO_ROOT/$FIXTURE_ID.wav" \
  --recognition-config "$RUN_ROOT/configurations/$CONFIG_ID.json" \
  --data-directory "$RUN_ROOT/isolated-data/$CONFIG_ID/$FIXTURE_ID" \
  --report-dir "$RUN_ROOT/reports/$CONFIG_ID/$FIXTURE_ID" \
  --single-expert-baseline
```

批量调度可读取 `commands.json` 中 argv，仅替换文档中的占位变量，不使用 `eval`。A–E 不能降级成无 GPT 的旧基线。D 保持 `multilingualASR`，等待原生单专家校验支持它，不通过改角色冒充中文或英文专家。原生导出文件名是运行时 recording UUID，索引器从每个配置/音频的 report 目录发现它：

```sh
python3 -B "$EVAL/harness.py" index --run-root "$RUN_ROOT" \
  --native-source-commit "$NATIVE_SOURCE_COMMIT" --output "$RUN_ROOT/trace-index.json"
python3 -B "$EVAL/harness.py" score --index "$RUN_ROOT/trace-index.json" \
  --output "$RUN_ROOT/scored.json"
```

索引只接收已有导出，不创建假 trace。同一配置/音频出现多个导出会拒绝，不能按分数选择最佳重试。索引含本地路径，不属于公共报告；已提交报告只用相对路径和占位变量。准备配置与授权后的实际配置是不同证据：索引冻结实际完整配置，评分校验 trace、索引、UUID、模型、参数、原生 source commit、音频 ID/hash/尺寸及参考 hash。每配置跨音频的实际配置必须一致。

## 报告数据契约（schema_version 1）

- `preflight.json`：原生源码检查时的提交、冻结 manifest/plan/标注哈希、父流程元数据及哈希、独立云阻断、磁盘计数、历史结果收据；`preflight-audio-integrity.json` 是逐文件明细。WAV 文件 hash 与 PCM payload hash 分开记录，不转码或改写音频。
- `score`：`evaluator_source_commit`、评分文件哈希、`native_source_commit`、参考标注哈希和 A–E 配置规范；F 单列 `NOT_AVAILABLE`，`metrics=null`。无 trace 时是 `NOT_RUN`，性能/误差率为 null；已观测的零错误才允许 0。`summary-only` 省略逐条及配对明细，完整模式保留 120 个槽位。
- 每音频行：音频/参考 hash、trace hash、原生提交、实际完整配置及独立规范化配置 hash。保留原生配置 hash 收据，不声称它等于 Python JSON 序列化 hash。
- `raw_asr`：逐 run/candidate/sequence 的原始文字和时间；只有完整、EOS 后、完整音频范围才用完整参考评分。部分输出不拿整句 gold 冒充时间对齐真值。
- `gpt_reviews`：唯一 GPT 的 usage/run、响应证据、耗时、run 状态。可核验的单一完整候选 UTF-16 全范围选择可评分；部分、多段拼接、缺失响应保持 null 并保留证据。本工具不重建原生融合算法，不将未接受的 GPT 选择说成已发布文字。
- `gpt_error_pairs`：同一参考/音频、GPT 当时实际审阅的完整原始候选，对比 GPT 选择；记录修复位置、新增错误位置、MER 差值及术语/数字/否定/单位变化。保留每候选、每次复核，不把重复 revision 累加成独立音频统计。
- `revisions` 与 `stages`：保留同代次 fusion decisions，以及现有 evaluator 的首预览、说话中修订、稳定前缀、最终文字。最终文字是流水线结果，不因配置了 GPT 就断言每个字来自 GPT。失败保持 `FAILED` 与服务状态；无最终输出不伪造空字符串评分（这里显式覆盖旧 scorer 的失败遗漏惩罚策略）。
- `comparisons`：A→C、B→C、C→D、C→E、D→E 的同音频配对误差与延迟。C→D 为多专家组合替换，不是单变量消融。源提交、音频或共享模型参数不一致则排除。先逐音频相减，再汇总分位数；缺失端点是 null，不是 0 秒。持久化时间不是 UI 渲染、端到端麦克风或投递确认。

CER/WER/MER 及 critical 项均沿用冻结指标；中文空格 WER 不是中文分词基准。词面命中、插入、重复与“GPT 修复”均为参考对齐代理指标，不代表语义真值；流畅不等于正确。没有独立语义标签时 semantic hallucination 仍未测。缺少 trace 的槽位不推断曾成功或失败；导出前失败需保留原生进程日志另审。索引验证是证据一致性检查，不是对文件来源的密码学认证。

没有新增语料、合成正式结果、云请求、服务或部署；远端状态按本次“全部本地”指令未查询。真实 A–E 性能、实际全量 PCM 分发和原生 Mac 验收均不能由这些 Python 测试代替。
