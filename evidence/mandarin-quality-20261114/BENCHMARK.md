# M5 同音频工程验收

机器为 24 GiB Apple M5。基线窗口使用运行中的 0.12 所对应的签名包、独立临时目录和公开语料。候选窗口使用独立 Bundle ID 的签名包。每次观察新建应用进程、使用一个本地模型。模型与程序身份在 [机器清单](bench-identity.json)，语料授权、来源、变换及原始 SHA 在[语料说明](../mandarin/SOURCES.md)。

## 原速文字窗口

输入按墙钟以 20 ms 帧进入采集环。探针取已布局的 NSTextView 文字，能区分时间轴发布与实际显示。已知参考双字首次出现在讲话中才计首次有效更新。间隔 P95 在有效更新之间计算。每条的最长停显也含声学起点到首更、末更到声学终点。EOS 使用输入文件结束时刻，文件内尾部静音与人工标注的讲话结束可能不同。完整收据均记录时间轴、窗口时间和每段实际引擎。应用内绘制快照仅取隔离窗口的公开语音。

以 15 段不同原速音频为一组。每组为 6 段 FLEURS、4 段 ASCEND 普通话及 5 段 ASCEND 中英混说，共 568 个参考字符。CER 沿用原计分器的 NFKC、大小写与标点规则。保留转写中的简繁差异、空白结果与原生探针退出码。Qwen 0.6B 的净改善包含一个样本中 8 处简繁差异。原音包含英文人名的个例中，1.7B 正确还原 Houston Rockets 和 McGrady，0.6B 仍将其听成 Houston Rockies 和 McGready。单条个例不代表整个类别。

候选 Apple 的初次 15 个窗口都记录为零次更新。新 Bundle ID 没有完成语言资源准备。原失败逐条在 [准备前收据](apple-before-reservation)。同一应用调用 Apple 原生准备流程后退出，再次启动。在同一 15 条上的新结果列入候选窗口指标。

## 批量质量与稳定性

原生 MandarinCohort 使用相同公开 WAV，分别直接给一个识别会话，以及经采集转换、VAD、原音、SQLite 和文字流发布。每条均经过实际 ASR，批量测试采用加速帧喂入。它可以暴露产品队列和分段问题，其吞吐、时间和 CPU 不可替代原速结论。420 段原始样本包括 160 条 FLEURS、160 条 ASCEND、100 条 AISHELL-1。另有固定的 20 条低音量及加噪变换。每组汇总保留删除、替换、插入、空白、混说 MER 与数字、否定等逐字匹配指标。逐字匹配不能鉴定两个不同表述意义相同，插入数也不能直接当幻觉数。

运行时指标取无竞争 Saytile 推理的独占时段。系统共享服务、GPU、ANE 和整机功耗来自 Mac 上采样，与同次紧邻的空闲对照同时保留；其它系统活动仍有影响。对比峰值采用同一时刻 App 和 helper 的物理内存，用 MiB 表示。15 分钟连续测试另外对原速输入、实际 SQLite 外键、每个原音文件的帧数、模型和窗口写收据。现场个人口音、8 GiB 真机及电池整日续航未在该机测得。

## 复现

1. 按 [评测脚本说明](../../scripts/mandarin/README.md) 取得固定语料并核验权重。在两个对应源码上分别编译链接 MandarinCohort 并构建原生签名 App。每种源码、模型与方法都另设输出目录。执行脚本时每次只运行一个模型。
2. 用 scripts/test-local-panels.py 指定签名 App、模型及 ../mandarin/panel-cohort.json，选择全部 15 段。权重只从固定 SHA 的测试目录克隆到临时目录。命令给 --models apple sherpa qwen-small，候选另加 qwen-large。
3. 对每个模型运行 scripts/mandarin/run-cohort.sh MODEL paired 和 MODEL aishell。文件放入对应的 runs 子目录，原速收据放 panels。每个批量记录含样本 ID、版本来源、最终文字、全部识别状态及错误。
4. 运行 python3 scripts/mandarin/paired-quality.py --receipts <该版本目录> --wav <语料目录> --source <源码SHA> --out <metrics.json>。脚本只汇总完整且哈希匹配的原速组，420 段和 20 个派生的加速指标分开计，不把未测文件填成成功。
5. 资源测试使用 scripts/mandarin/power.py、macmon 0.11.0 及同一段大于等于 10 秒的人声。长稳测试使用 scripts/mandarin/quality-soak.py --app <签名App> --weights <权重> --wav <语料> --manifest evidence/mandarin/panel-cohort.json --output <收据> --model <模型>。

批量、原速和长稳收据各自绑定运行时源码。在后续产品构建上修改选择策略、错误接替或首次资源准备时，应另行验证该包的真实路由和原生窗口，保留原始测量 SHA。
