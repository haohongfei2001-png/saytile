# PR #4 离线四阶段质量评估

本目录只读取明确指定的现有 manifest、旧结果和诊断 JSON。评分、选样与准备命令**不读取原音、不调用云服务、不读取 Keychain/UserDefaults、不执行 App**。测试使用独立合成 fixtures。它没有产生新的云端准确率、时延或融合收益结论。

## 复跑

从仓库根目录执行，Python 标准库即可：

```sh
python3 -m unittest discover -s research/asr/benchmark/quality-evaluation -p 'test_*.py' -v
python3 research/asr/benchmark/quality-evaluation/plan.py \
  --output research/asr/benchmark/quality-evaluation/plan.json
python3 research/asr/benchmark/quality-evaluation/evaluate.py \
  --plan research/asr/benchmark/quality-evaluation/plan.json \
  --output research/asr/benchmark/quality-evaluation/legacy-112-report.json
```

`plan.json` 固定原 manifest 的 SHA-256、全部 112 个原始真人 ID、音频哈希、旧输出 receipt、24/48/112 档名单和配置。112 条为中文 36、英文 36、中英混说 40；24/48 档分别每种语言 8/16 条，24 是 48 的前缀。选择仅基于原有语言、group、有效预标关键项、说话者与固定哈希顺序，**不根据模型成绩挑样**。这是带挑战项的有目的抽样，不是总体准确率的无偏估计。

旧三组 112 条输出校验其原 receipt 与逐条音频哈希后评分。`legacy_qwen_mlx_1_7b_bf16` 始终标明本地 `mlx-community/Qwen3-ASR-1.7B-bf16`；它不提供 `A_qwen_cloud` 的任何测量值。已知语言的 Apple 配置标为 oracle，不冒充产品自动语言路由。

## 四阶段与时序口径

| 阶段 | 选取规则 | 可以测什么 |
|---|---|---|
| 首次临时文字 | 本代首次非空 fusion preview decision | 持久化首预览时间；不是 UI 渲染时间 |
| 讲话中的修正 | 最后一包音频提交前，最后一次不同于前次的 preview | 对应文字与时间；没有变化时不是捏造一次修正 |
| 可输入稳定前缀 | 本代首次非空、outcome=published 的 stableText | 稳定资格形成时间；不是外部投递确认 |
| 完整定稿 | 本代 terminal=completed、resolved=true、选中 final revision 与 selectedText 一致 | 整句 CER/WER/MER 与真实完成延迟；archive/deferred 的最终文字不冒充已外发 |

**阶段 1–3 缺少独立时间对齐 gold 时，准确率为 `null / NOT_RUN_NO_TIME_ALIGNED_REFERENCE`。** 不能对临时前缀套完整句参考，把尚未说出、尚未显示或尚未稳定的后半句计成识别漏字。报告中的 `full_reference_coverage_diagnostic` 只提供覆盖观察，故意不提供错误率。

未来工程可在 manifest 的独立副本增加 `reference_timed_units`（text、start_seconds、end_seconds）与 `reference_timing_annotation_id`，并给具体 decision 增加经验证的 `referenceAudioRange`。范围切开一个参考单位时仍拒绝评分。`audioSubmittedSeconds`/frames 是输入进度，**不等于输出前缀的声学终点**，不能拿它自动制造参考文字范围。不要求用户标注、录音或用私人讲话填补这一缺口。

时序以 exportTrace 的 epoch 毫秒为准：分别输出相对 replay 起点、首包提交的首预览/首稳定，完成相对末包提交的延迟，以及 session termination。真实 terminal 时间独立于 `sessionEndedAt`；缺失不以 session 终止时间代替。UI 首显和麦克风 onset 未测时维持 null。旧 direct-file 的 elapsed/events 不进入实时延迟统计。

## 指标与配对

- 继承旧 scorer 的冻结 NFKC/casefold/标点规则，不改写数字、否定、填充词、繁简或同义词。每条都给 CER、空格分词 WER、统一 MER；中文主要看 CER，英文主要看 WER，混说及跨语言整体看 MER。中文空格 WER 不叫中文分词 WER。
- 报告微平均 S/D/I、原参考 token 漏字、插入代理与参考之外的相邻重复代理。真实参考中的重复不作为“去重”对象。
- 数字/否定/单位/术语使用推理前已有 accepted_forms，按完整词/token 及出现次数匹配，分别报告遗漏与额外重复次数；关键项另保留 °/%/单位符号，不把 °C 简化为字母 C。gold 中没有该项的注释列 `INVALID_REFERENCE_ANNOTATION`，不计漏词。
- **插入不是语义幻觉的证明。** 未有独立人工语义审阅时，语义幻觉率保持 null。现有真人集合没有单位注释，因此单位率同样 `NOT_RUN`；合成单位测试只验证评分代码。
- 同音频、同阶段、同 gold 范围配对，列出逐参考位置修复/新引入的错误、关键项恢复/丢失和每条 MER 变化。删除变成错词不是修复；总 MER 相同仍可同时修好一处、弄错另一处。
- 配对共有模型的参数指纹改变时排除该条，避免把地域、上下文或推理设置的变化混入一次模型增减。每个配置跨片段的完整配置 SHA 改变时拒绝合并。
- 无确认定稿的已结束失败会计入整句缺失，不把失败样本静默删除。服务失败按实际 terminal attempt 计数，取消/中断单列；“完全没有稳定发布”与“未形成完整定稿”分别统计。无运行不填零失败率。

## 配置矩阵与调用量

`plan.json` 包含 11 个候选配置：A Qwen 云单独、B Assembly 单独、C 双专家、D C+Soniox、E D+AI、F E+Gemini、G F+Scribe、H C+AI、Meta 单独、Qwen+Meta 替换英文专家、Soniox 单独。C→D、D→E、E→F、F→G、C→H、H→E 分离增量；单专家与双专家对照保留。Soniox 单独→D 是增加两个专家的整体对照，明确不是单专家消融。

所有配置保持最高质量模式。单专家只经诊断入口的显式 `--single-expert-baseline` 放行，仍检查恰好一个实时专家、型号/地域/工作区及逐服务授权；生产 UI 的默认验证仍要求中文和英文专家。结果用 `configurationIdentity.evaluationMode` 区分，不能偷偷切成 fast 或伪装成双专家。

`planned_workloads` 按三档汇总每服务/model 的片段覆盖数、流式 session 数、音频秒数和复核的一轮完整音频当量。24 档是 198.980125 秒独立音频、264 个配置×片段计划、528 条流式 session；这些都**没有执行**。AI、Gemini 和文件 ASR 可对多个变化中的 PCM 快照反复调用，所以动态调用数/token 仍 null；一轮音频当量不是总预算。收费验证须有明确价格、费用授权与实际消费检查点。当前没有已验证的硬调用封顶机制；不能把准备计划写成保证不超额的预算。

## 只准备，不执行

```sh
python3 research/asr/benchmark/quality-evaluation/prepare.py \
  --plan research/asr/benchmark/quality-evaluation/plan.json \
  --panel 24 --outdir /tmp/saytile-quality-prepared \
  --audio-root /DECLARED_PUBLIC_CORPUS \
  --app /APPROVED_CANDIDATE/Saytile
```

只在 outdir 写入 11 个完整非秘密配置、`commands.json` 和调用量计划。所有 `cloudEnabled=false`、逐项 `cloudConsent=false`；Qwen 工作区是占位。配置 ID 与 App 推荐服务 ID 一致，不导出任何 Key。每个配置/片段使用独立 `--data-directory`；已有准备文件被人为修改时拒绝覆盖。程序不执行这些 argv，也不更改 UserDefaults。

后续工程执行前须具备明确的云处理/费用授权、服务 Keychain Key、工作区及实际消费检查方案，再在审核过的配置副本显式开启。如果授权要求不可超越的硬上限，必须先验证相应执行约束，不能以人工检查点冒充硬限额。没有凭据/授权时停留在准备状态，不能靠运行脚本“试一下”。这里只留下复跑入口，不要求用户现在开通账户或交付私人资料。

## 接入真实 trace

导出 schema 2 包括 `source`（fixtureID、整 WAV SHA、sampleRate、frameCount）、完整非凭据 `configuration`、`configurationIdentity`（sha256/evaluationMode）、真实 Bundle sourceRevision（否则缺失）、generation-scoped finalization 和全部候选/decision/run。旧代次不能改善本代分数。缺少来源、配置或代次证据时不评分。

显式索引例子（填入实际文件散列，不使用占位执行）：

```json
[{"configuration_id":"C_dual","fixture_id":"ascend-01047",
  "trace_path":"/EXPLICIT_REPORT_DIRECTORY/actual-recording-id.json",
  "trace_sha256":"ACTUAL_EXPORTED_JSON_SHA256"}]
```

```sh
python3 research/asr/benchmark/quality-evaluation/evaluate.py \
  --plan research/asr/benchmark/quality-evaluation/plan.json \
  --panel 24 --trace-index /EXPLICIT_INDEX.json --no-legacy \
  --output /EXPLICIT_REPORT.json
```

重复 configuration/fixture 索引会被拒绝：重试必须明确选择 attempt，不能用最后一条覆盖失败。批量比较仍保留 missing、失败和无法稳定的比例，不以最后稿流畅度代替准确性。

## 验证范围

Python 26 项测试覆盖冻结编辑距离、关键项边界/单位/出现次数、重复、修复与新错并存、旧代次过滤、真实/缺失时序、配置错配、失败计数、独立同音频配对、嵌套选样、旧本地 Qwen 身份及禁用准备模板；日志 `python-tests.log`。Swift 5 项诊断测试（原 2 + 新 3）在父线统一运行中通过，覆盖云权限边界、流式整文件哈希、明确单专家验证及真实 terminal/代次导出；这 5 项不能代替全量测试结论。

`fixtures/trace-synthetic.json` 是评分程序的合成契约 fixture，**不是模型调用产物或质量成绩**。实际旧结果复评分见 `LEGACY-RESULTS.md` 与 `legacy-112-report.json`。
