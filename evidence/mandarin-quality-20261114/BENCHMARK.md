# M5 同音频工程验收

机器为 24 GiB Apple M5。基线窗口使用运行中的 0.12 所对应的签名包、独立临时目录和公开语料。候选窗口使用独立 Bundle ID 的签名包。每次观察新建应用进程、使用一个本地模型。模型与程序身份在 [机器清单](bench-identity.json)，语料授权、来源、变换及原始 SHA 在[语料说明](../mandarin/SOURCES.md)。

## 原速文字窗口

输入按墙钟以 20 ms 帧进入采集环。探针取已布局的 NSTextView 文字，能区分时间轴发布与实际显示。已知参考双字首次出现在讲话中才计首次有效更新。间隔 P95 在有效更新之间计算。每条的最长停显也含声学起点到首更、末更到声学终点。EOS 使用输入文件结束时刻，文件内尾部静音与人工标注的讲话结束可能不同。完整收据均记录时间轴、窗口时间和每段实际引擎。应用内绘制快照仅取隔离窗口的公开语音。

以 15 段不同原速音频为一组。每组为 6 段 FLEURS、4 段 ASCEND 普通话及 5 段 ASCEND 中英混说，共 568 个参考字符。CER 沿用原计分器的 NFKC、大小写与标点规则。保留转写中的简繁差异、空白结果与原生探针退出码。Qwen 0.6B 的净改善包含一个样本中 8 处简繁差异。原音包含英文人名的个例中，1.7B 正确还原 Houston Rockets 和 McGrady，0.6B 仍将其听成 Houston Rockies 和 McGready。单条个例不代表整个类别。

候选 Apple 的初次 15 个窗口都记录为零次更新。新 Bundle ID 没有完成语言资源准备。原失败逐条在 [准备前收据](apple-before-reservation)。同一应用调用 Apple 原生准备流程后退出，再次启动。在同一 15 条上的新结果列入候选窗口指标。

对 Qwen 0.6B 另设自动语言对照。它使用同一主程序、相同权重和 PCM，唯一推理设置变化是取消模型强制中文提示。这个包的 Info.plist 延用了对照标签；[机器清单](bench-identity.json) 单独记录替换的 worker 二进制与工作者源码 SHA。其结果存放在 unforced，不与基础候选合并。

## 批量质量与稳定性

原生 MandarinCohort 使用相同公开 WAV，分别直接给一个识别会话，以及经采集转换、VAD、原音、SQLite 和文字流发布。每条均经过实际 ASR，批量测试采用加速帧喂入。它可以暴露产品队列和分段问题，其吞吐、时间和 CPU 不可替代原速结论。420 段原始样本包括 160 条 FLEURS、160 条 ASCEND、100 条 AISHELL-1。另有固定的 20 条低音量及加噪变换。每组汇总保留删除、替换、插入、空白、混说 MER 与数字、否定等逐字匹配指标。逐字匹配不能鉴定两个不同表述意义相同，插入数也不能直接当幻觉数。

运行时指标取无竞争 Saytile 推理的独占时段。系统共享服务、GPU、ANE 和整机功耗来自 Mac 上采样，与同次紧邻的空闲对照同时保留；其它系统活动仍有影响。对比峰值采用同一时刻 App 和 helper 的物理内存，用 MiB 表示。15 分钟连续测试另外对原速输入、实际 SQLite 外键、每个原音文件的帧数、模型和窗口写收据。现场个人口音、8 GiB 真机及电池整日续航未在该机测得。

## 复现

1. 按 [评测脚本说明](../../scripts/mandarin/README.md) 取得固定语料并核验权重。在两个对应源码上分别编译链接 MandarinCohort 并构建原生签名 App。每种源码、模型与方法都另设输出目录。执行脚本时每次只运行一个模型。
2. 用 scripts/test-local-panels.py 指定签名 App、模型及 ../mandarin/panel-cohort.json，选择全部 15 段。权重只从固定 SHA 的测试目录克隆到临时目录。命令给 --models apple sherpa qwen-small，候选另加 qwen-large。
3. 对每个模型运行 scripts/mandarin/run-cohort.sh MODEL paired 和 MODEL aishell。设置 SAYTILE_BENCH_RESULTS 指向对应的 runs 子目录，原速收据放 panels。每个批量记录含样本 ID、模型、最终文字、全部识别状态及错误；两份可执行文件指纹在机器清单。
4. 运行 python3 scripts/mandarin/paired-quality.py --receipts <该版本目录> --wav <语料目录> --source <源码SHA> --out <metrics.json>。脚本只汇总完整且哈希匹配的原速组。420 段和 20 个派生的加速指标分开计。scripts/mandarin/compare-paths.py 可基于两组 runs 复算引擎直通与归档差异、改善与退化个例。
5. 资源测试使用 scripts/mandarin/power.py、macmon 0.11.0 及同一段大于等于 10 秒的人声。长稳测试使用 scripts/mandarin/quality-soak.py --app <签名App> --weights <权重> --wav <语料> --manifest evidence/mandarin/panel-cohort.json --output <收据> --model <模型>。

最终安装包的原速窗口由自动选型触发。在第 4 步为该包加上 `--automatic`，可同时重建 [打包版原速、资源及完整直通/归档指标](delivery/metrics.json)。当各组原始记录齐备后，以下命令按样本 ID 比较最终归档与各个对照，保留空白、退步个例和按语料分层的配对区间。

```sh
python3 scripts/mandarin/compare-delivery.py --receipts evidence/mandarin-quality-20261114 --out /tmp/saytile-mandarin-defaults.json
```

批量、原速和长稳收据各自绑定运行时源码。在后续产品构建上修改选择策略、错误接替或首次资源准备时，应另行验证该包的真实路由和原生窗口，保留原始测量 SHA。

## 重建最终包的两条长句

[长句清单](delivery/extended/samples.json)含 25.74 秒的完整原始 WAV、五条公开录音的裁切起止帧及两个派生 WAV 的哈希。以下命令在已准备好 16 kHz 公开语料的工程根目录运行。输出目录仅用于这两条派生音频。

```sh
python3 - <<'PY'
import hashlib, json, pathlib, wave
root = pathlib.Path(".build/mandarin")
out = root / "long-replay"
out.mkdir(exist_ok=True)
sources = json.loads(pathlib.Path("evidence/mandarin-quality-20261114/delivery/extended/samples.json").read_text())["samples"]
item = next(row for row in sources if row["id"] == "continuous-public-5")
target = out / (item["id"] + ".wav")
with target.open("xb") as file, wave.open(file, "wb") as joined:
    joined.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
    for i, segment in enumerate(item["segments"]):
        original = root / "wav" / (segment["id"] + ".wav")
        assert hashlib.sha256(original.read_bytes()).hexdigest() == segment["source_wav_sha256"]
        with wave.open(str(original)) as reader:
            reader.setpos(segment["start_frame"])
            if i:
                joined.writeframes(bytes(1600))
            joined.writeframes(reader.readframes(segment["end_frame"] - segment["start_frame"]))
assert hashlib.sha256(target.read_bytes()).hexdigest() == item["audio_sha256"]
PY
python3 scripts/mandarin/prepare-tail-window.py .build/mandarin/long-replay/continuous-public-5.wav .build/mandarin/long-replay/trailing-quiet-481280.wav
```

将清单中剩余的完整 FLEURS 音频从 wav 语料目录复制到 long-replay；然后用上文的原速窗口命令，以 long-replay 为音频目录，选择 qwen-small、--automatic、--limit 3 及长句清单。每次运行都核验 WAV 哈希。批量复现最终结果时使用产品源码 cd41c60f、对应签名 App 的实际 helper、qwen-small 与固定 420 + 20 清单。原生探针所在目录需包含链接时生成的 Saytile_SaytileKit.bundle。
