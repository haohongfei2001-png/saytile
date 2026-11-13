"""Compare actual issued snapshots, decode occupancy and transient text on identical files."""
import argparse
import json
from pathlib import Path
import runpy

base = runpy.run_path(str(Path(__file__).resolve().parents[1] / "score-local-asr.py"))
norm, quant, rating = base["norm"], base["quant"], base["rating"]


def edits(events, onset, end):
    prefix_replacements = 0
    replaced_or_removed = 0
    previous = ""
    for item in events:
        text = norm(item["text"])
        if not onset <= item["t"] < end or not text or text == previous:
            continue
        if "speaking" in item and not item["speaking"]:
            continue
        if previous and not text.startswith(previous):
            prefix_replacements += 1
            align = rating(previous, text)
            replaced_or_removed += align["deletions"] + align["substitutions"]
        previous = text
    return {"suffix_revisions": prefix_replacements, "removed_or_replaced_chars": replaced_or_removed}


def collect(directory, summary, ident):
    measurements = next(item for item in summary["rows"] if item["id"] == ident)
    raw = json.loads((directory / ("auto-qwen-small-" + ident + ".json")).read_text())
    assert raw["exit_code"] == 0 and raw["sha"] == summary["source"] and raw["audio_sha256"] == measurements["sha256"]
    assert raw["recordStates"] and all(state == "completed" for state in raw["recordStates"])
    ds = [d for e in raw["rawWorkerEvents"] for d in (e.get("decodes") or []) if not d["final"]]
    assert ds
    duration = sum(d["endUptime"] - d["startUptime"] for d in ds)
    output = {"preview_decodes": len(ds), "preview_decode_wall_s": round(duration, 4),
              "audio_wall_s": round(raw["endOfFile"], 4),
              "timeline_revisions": edits(raw["publications"], measurements["onset"], measurements["end"]),
              "screen_revisions": edits(raw["frames"], measurements["onset"], measurements["end"]),
              "first_visible_s": measurements["display"]["first_s"],
              "publications": measurements["timeline"]["count"], "published_gaps_s": measurements["timeline"]["gap_s"],
              "longest_published_s": measurements["timeline"]["longest_s"], "final_after_eof_s": measurements["after_file_s"]}
    return output, raw["archive"]


def compare(old, new):
    report = {}
    for group in ("panels", "extended"):
        rows = []
        before, after = (json.loads((d / (group + ".json")).read_text()) for d in (old, new))
        assert {r["id"] for r in before["rows"]} == {r["id"] for r in after["rows"]}
        for item in before["rows"]:
            pair = [collect(d / group, summary, item["id"]) for d, summary in [(old, before), (new, after)]]
            rows.append(dict(id=item["id"], sha256=item["sha256"], identical_archive=pair[0][1] == pair[1][1],
                             before=pair[0][0], after=pair[1][0]))
        out = dict(rows=rows, identical_archives=sum(r["identical_archive"] for r in rows))
        for key in ("before", "after"):
            group_values = [r[key] for r in rows]
            acc = {f:round(sum(v[f] for v in group_values), 3)
                   for f in ("preview_decodes", "preview_decode_wall_s", "audio_wall_s", "publications")}
            acc["decode_wall_ratio"] = round(acc["preview_decode_wall_s"] / acc["audio_wall_s"], 4)
            for layer in ("timeline_revisions","screen_revisions"):
                acc[layer] = {k:sum(v[layer][k] for v in group_values) for k in group_values[0][layer]}
            acc["first_visible_s"] = quant([v["first_visible_s"] for v in group_values if v["first_visible_s"] is not None])
            acc["final_after_eof_s"] = quant([v["final_after_eof_s"] for v in group_values])
            acc["longest_published_s"] = max(v["longest_published_s"] for v in group_values)
            out[key] = acc
        report[group] = out
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for opt in ("old","new","out"):
        parser.add_argument("--" + opt, type=Path, required=True)
    a = parser.parse_args()
    a.out.write_text(json.dumps(compare(a.old, a.new), ensure_ascii=False, indent=2) + "\n")
