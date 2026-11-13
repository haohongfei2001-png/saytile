"""Summarize official ASR scores and inspect specific public transcripts. No inference."""
import argparse
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
fixtures = root / "evidence/mandarin"
variants = [
    ("Apple 0.12", "baseline", "apple"),
    ("0.6B 固定中文", "candidate", "qwen-small"),
    ("0.6B 不指定语言", "unforced", "qwen-small"),
    ("1.7B 固定中文", "candidate", "qwen-large"),
]
illustrations = {
    "金额数量级": "aishell1-test-fd654755de8d25fe",
    "数字格式与货币单位": "aishell1-test-5bcb273927a4b5f6",
    "数字、时长": "fleurs-7880bd7fe5dcd286",
    "增添否定": "ascend-zh-e2c8b5080e64fd8c",
    "漏掉否定": "ascend-zh-0c5639a6e24f539b",
    "专业词": "ascend-zh-1fc44c4f2b843c04",
    "有意重复": "ascend-zh-923c1789649f5185",
    "新增局部重复": "fleurs-9b5173ba93decd31",
    "整条缺失": "fleurs-1bc3201a9f24a2fe",
    "漏掉句尾": "aishell1-test-d30e082521775278",
    "把英文译为中文": "ascend-mixed-6185571719fdd11b",
}


def read(path):
    return json.loads(path.read_text())


def collect(folder):
    refs = {r["id"]: r for group in ["paired", "aishell"] for r in read(fixtures / f"{group}.json")
            if r["source"] not in {"quiet", "noise15db"}}
    assert len(refs) == 420
    examples = {case: {"id": key, "reference": refs[key]["reference"], "wav_sha256": refs[key]["audio_sha256"]}
                for case, key in illustrations.items()}
    evaluations = {}
    for label, variant, model in variants:
        summary = read(folder / variant / "metrics.json")
        for method in ["product", "direct"]:
            run = summary["accelerated"].get(f"{model}-{method}", {})
            key = f"{label} / {method}"
            if "original_420" not in run.get("cohorts", {}):
                evaluations[key] = {"status": "NO_COMPLETE_SCORE"}
                continue
            rows = {}
            for manifest in ["paired", "aishell"]:
                relpath = f"runs/{manifest}-{model}-{method}.jsonl"
                data = (folder / variant / relpath).read_bytes()
                assert hashlib.sha256(data).hexdigest() == summary["files_sha256"][relpath], relpath
                for row in map(json.loads, data.splitlines()):
                    if row["id"] in refs:
                        assert row["id"] not in rows and row["path"] == method and row["model"] == model
                        rows[row["id"]] = row
            assert set(rows) == set(refs)
            evaluations[key] = {"status": "SCORED", "source": summary["source"], "scorer_input_directory": variant,
                                "alignment": run["cohorts"]["original_420"],
                                "exact_anchor_tokens": run["exact_anchor_tokens"]["original_420"],
                                "mixed_mer": run["by_manifest"]["paired"]["mixed_mer"],
                                "mixed_rows": run["by_manifest"]["paired"]["groups"]["ascend-mixed"]["rows"],
                                "empty_output_ids": [i for i, r in rows.items() if not r["text"].strip()]}
            for case, example in examples.items():
                example[key] = rows[example["id"]]["text"]
    return {"scope": "420 natural public utterances. The 20 synthetic acoustic transformations are excluded.",
            "scoring_sources": ["scripts/mandarin/paired-quality.py", "scripts/mandarin/score.py"],
            "variants": evaluations, "examples": examples}


def render(report):
    entries = report["variants"]
    headings = [v[0] for v in variants]
    lines = ["# 数字、否定、术语与原话保留", "",
             "同一批 420 段有授权的人声经加速送入完整 VAD、识别与 SQLite 归档。统计只含独立原音。混说另按 80 段 ASCEND 的 MER 计算，英文按词，汉字按字。", "",
             "| 产品归档 | " + " | ".join(headings) + " |", "|---" + "|---:" * len(headings) + "|"]

    def measure(title, measure_value):
        values = []
        for label in headings:
            entry = entries[label + " / product"]
            values.append(str(measure_value(entry)) if entry["status"] == "SCORED" else "待完整收据")
        lines.append("| " + " | ".join([title, *values]) + " |")

    def anchor_pair(item):
        return f"{item['missing']} / {item['extra']}"

    measure("中英混说 MER（1,166 单位）", lambda v: f"{100*v['mixed_mer']['mer']:.2f}%")
    for name, key, n in [("数字", "number", 249), ("货币词", "money", 11), ("否定词", "negative", 112),
                         ("日期时间词", "date_time", 41), ("技术词", "technical_term", 11),
                         ("拉丁字词", "latin", 237)]:
        def pair(v, category=key, count=n):
            a = v["exact_anchor_tokens"][category]
            assert a["reference"] == count
            return anchor_pair(a)
        measure(f"{name}漏项 / 多项（参考 {n} 次）", pair)
    measure("整段空白数 / 420", lambda v: len(v["empty_output_ids"]))
    measure("对齐删除 / 插入字数（参考 10,663 字）",
            lambda v: f"{v['alignment']['deletions']} / {v['alignment']['insertions']}")
    lines.extend(["", "“漏项 / 多项”沿用冻结评分器，逐句比较原样词项的出现次数。六万元写作 ¥60,000 也会计入表中。表里的“无”含“无人机”等构词；插入字数也包括有依据的口语表达。原始转写与对齐结果都保留。", "",
                  "## 同一录音中的错误", "",
                  "- **金额与时间。** AISHELL 的“四亿元”被旧 Apple 记为 400000，两种 0.6B 均保留四亿元。另一条 FLEURS 的“10–60 分钟”，旧 Apple 保留两个数，两种 0.6B 均把 10 写成 15。",
                  "- **否定与重复。** 原话“是不是平时学得都是”被旧 Apple 写成“是不是平时学的都不是”，两种 0.6B 保留“都是”。另一句“我我不就是”三者都漏掉“不”。“那你们你们”三者都只保留一个完整的“你们”。另一段 FLEURS，两种 0.6B 在句尾新增“静物的静物的”，参考为“顿悟的境界”。",
                  "- **漏句。** FLEURS 罗曼语句在旧 Apple 的加速归档中为空，它在实际语速下能出字。AISHELL 的“最大的无人机之一”在三者中都于“最大”截断。整段有字并不能排除句尾丢失。",
                  "- **混说。** 指定中文的 0.6B 将一整段英文翻为中文，解除语言限制后保留英文，但仍有漏词和误词。1.7B 在该反例的原速窗口中保留英文。", "",
                  "## 覆盖边界", "",
                  "参考里的 11 个货币词只有“元”和“美元”。11 个技术词只覆盖“软件、病毒、AI、网络”。缺少港币、欧元、药物规格、个人姓名、个性化术语的足量对照。没有本人自然语音人工真值，也没有给全部 420 段做语义重复或漏句的人审标注。", "",
                  "每条例句保留公开样本 ID、WAV 校验值、完整原文、收到的模型直出和产品归档。[逐项证据](semantic-cases.json) · [原速语言提示对照](language-ab/README.md) · [批量及原速对照](BENCHMARK.md)"])
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipts", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--markdown", type=Path)
    args = parser.parse_args()
    report = collect(args.receipts)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    if args.markdown:
        args.markdown.write_text(render(report))
