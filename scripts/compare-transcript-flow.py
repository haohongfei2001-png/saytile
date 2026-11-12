#!/usr/bin/env python3
"""Compare native screens on the same public audio. Host publications and observed paints are different clocks."""
import argparse, hashlib, json, pathlib, runpy
from collections import Counter

p = argparse.ArgumentParser(description=__doc__)
for name in ("cohort", "audio", "baseline", "candidate", "out"):
    p.add_argument("--" + name, type=pathlib.Path, required=True)
a = p.parse_args()
score = runpy.run_path(str(pathlib.Path(__file__).with_name("score-local-asr.py")))
read, quant, norm = (score[key] for key in ("read", "quant", "norm"))
samples = read(a.cohort)["samples"]
assert samples and len({s["id"] for s in samples}) == len(samples)

def summary(folder, has_publications):
    rows, gaps, bursts, source_revs, totals = [], [], [], set(), Counter()
    for sample in samples:
        id = sample["id"]
        wav = a.audio / (id + ".wav")
        r = read(folder / ("apple-" + id + ".json"))
        assert hashlib.sha256(wav.read_bytes()).hexdigest() == r["audio_sha256"] == sample["audio_sha256"]
        assert r["id"] == id and r["exit_code"] == 0 and r["providers"] == ["apple-speech-analyzer"]
        source_revs.add(r["sha"])
        onset, end = score["acoustic"](wav)
        ref, active = norm(sample["reference"]), []
        for f in r["frames"]:
            t, text = f["t"], norm(f["text"])
            if f["speaking"] and onset <= t < min(end, r["endOfFile"]) and text and (not active or text != active[-1][1]):
                active.append((t, text))
        matched = [t for t, text in active if score["useful"](ref, text)]
        per_gaps = [b[0]-v[0] for v,b in zip(active,active[1:])]
        # Count only semantic appends: replacing a bad guess is a correction, not a typing burst.
        appends = [len(text)-len(old) for (_,old),(_,text) in zip(active,active[1:]) if text.startswith(old)]
        gaps += per_gaps
        bursts += appends
        archive = "".join(reversed(r["archive"]))
        totals.update(score["rating"](sample["reference"],archive))
        row = dict(id=id, first_reference_bigram_after_onset_s=round(matched[0]-onset,3) if matched else None,
                   pre_end_screen_changes=len(active), screen_append_chars=quant(appends), screen_gap_s=quant(per_gaps),
                   max_screen_gap_s=round(max(per_gaps),3) if per_gaps else None,
                   archive_empty=not bool(archive.strip()), empty_archive_segments=sum(not s.strip() for s in r["archive"]))
        if has_publications:
            pubs = r["publications"]
            assert pubs and r["frames"] and pubs[-1]["text"] == r["frames"][-1]["text"], id
            row.update(host_text_publications=len(pubs), sampled_changes=len(r["frames"]),
                       first_publication_to_first_screen_observation_ms=round((r["frames"][0]["t"]-pubs[0]["t"])*1000,1))
        rows.append(row)
    assert len(source_revs) == 1
    result = dict(source=source_revs.pop(), samples=len(rows), with_reference_text_during_speech=sum(r["first_reference_bigram_after_onset_s"] is not None for r in rows),
                  first_reference_bigram_after_onset_s=quant([r["first_reference_bigram_after_onset_s"] for r in rows if r["first_reference_bigram_after_onset_s"] is not None]),
                  pre_end_lexical_screen_changes=sum(r["pre_end_screen_changes"] for r in rows),
                  observed_append_size_characters=quant(bursts), observed_gap_s=quant(gaps),
                  worst_inter_update_gap_s=round(max(gaps),3) if gaps else None,
                  empty_archive_segments=sum(r["empty_archive_segments"] for r in rows), archived=score["pooled"](totals), rows=rows)
    if has_publications:
        result["first_host_publication_to_first_screen_observation_ms"]=quant([r["first_publication_to_first_screen_observation_ms"] for r in rows])
    return result

result=dict(method="Real-time replay of hash-matched public audio into a single on-device Chinese Apple SpeechAnalyzer, isolated native Saytile window and archive. Microphone and paid services not used. Screen sampled ~35 ms; distinct lexical changes only during sustained signal and actual speaking state. Append lengths exclude replacements. Host notifications measure timeline updates, not new model tokens. Nearest-rank quantiles across 10 clips are descriptive, not general accuracy or latency claims.",
            corpus=samples,baseline=summary(a.baseline, False),candidate=summary(a.candidate, True))
a.out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
