#!/usr/bin/env python3
"""Recompute the M5 source-bound product/worker comparison from original licensed waves and raw receipts."""
import argparse, collections, hashlib, json, pathlib, runpy, wave
from array import array

ROOT = pathlib.Path(__file__).resolve().parents[1]
V1 = runpy.run_path(str(ROOT/"research/asr-2026-11-06/scripts/score.py"))
norm = lambda s: "".join(V1["tokenize"](s, "cer"))
align, pct = V1["align"], V1["percentile"]
keys = ("errors", "substitutions", "deletions", "insertions", "reference_units")
models = "apple sherpa nemotron-metal qwen-small paraformer sensevoice qwen-large".split()
live = models[:4]
# Additional reference-only anchors, scored separately from the pre-existing corpus annotations.
# Chinese or Arabic renderings count for the lexical number checks, not for literal CER.
anchors = {
    "4719524538529342597": [("number","29",["29岁","二十九岁","廿九岁"]),("number","15",["15","十五"]),("unit","英里",["英里"]),("proper_name","Malar Balasubramanian",["Malar Balasubramanian"])],
    "870219628413797707": [("number","三部分",["三部分","3部分"])],
    "16549419822262830660": [("negation","不活跃",["不活跃"]),("term","罗斯贝数",["罗斯贝数"])],
}
def quant(values):
    return {f"p{p}": round(pct(values,p/100),3) if values else None for p in (50,95)}
def pooled(m):
    return {**{k:m[k] for k in keys}, "cer":round(m["errors"]/m["reference_units"],5) if m["reference_units"] else None}
def rating(ref, hyp):
    return {k:v for k,v in align(norm(ref),norm(hyp)).items() if k in keys}
def changes(texts):
    prev=""; edits=comparisons=0; retreated=0
    for text in map(norm,texts):
        if not text or text==prev: continue
        if prev:
            comparisons+=1
            if not text.startswith(prev):
                edits+=1
                i=0
                while i<min(len(text),len(prev)) and text[i]==prev[i]: i+=1
                retreated+=len(prev)-i
        prev=text
    return dict(comparisons=comparisons,tail_replacements=edits,characters_retracted=retreated)
def useful(ref, text):
    # Excludes one-character filler, punctuation and prefixes unrelated to the reference.
    return any(ref[i:i+2] in text for i in range(len(ref)-1))
def acoustic(path):
    with wave.open(str(path)) as w:
        assert (w.getnchannels(),w.getframerate(),w.getsampwidth()) == (1,16000,2)
        v=array("h",w.readframes(w.getnframes()))
    threshold=32768*10**(-55/20)
    blocks=[v[i:i+320] for i in range(0,len(v),320)]
    hot=[sum(x*x for x in b) >= len(b)*threshold**2 for b in blocks]
    active=[i for i in range(len(hot)-2) if all(hot[i:i+3])]
    if not active: raise ValueError("no sustained onset")
    return active[0]*.02,min(len(v)/16000,(active[-1]+3)*.02)
def read(p):return json.loads(p.read_text())
def frontend(m,d,refs,audio,sha):
    delays,any_delays,from_file,gaps,rows=[],[],[],[],[]
    churn,archive=collections.Counter(),collections.Counter()
    for sample in refs:
        i=sample["id"]; ref=norm(sample["reference"])
        p=next(d.glob(f"{m}-{i}.json")); ui=read(p)
        assert ui["sha"]==sha and ui["exit_code"]==0 and ui["audio_sha256"]==sample["audio_sha256"]
        assert ui["providers"]==["apple-speech-analyzer" if m=="apple" else m]
        path=audio/(i+".wav"); assert hashlib.sha256(path.read_bytes()).hexdigest()==ui["audio_sha256"]
        onset,end=acoustic(path)
        frames=[f for f in ui["frames"] if f["t"]<ui["endOfFile"] and f["speaking"]]
        distinct=[]
        for f in frames:
            text=norm(f["text"])
            if text and (not distinct or text!=distinct[-1][1]): distinct.append((f["t"],text))
        matched=[t for t,s in distinct if useful(ref,s) and t>=onset]
        if matched: delays.append(matched[0]-onset);from_file.append(matched[0])
        any_after=[t for t,s in distinct if t>=onset]
        if any_after:any_delays.append(any_after[0]-onset)
        gaps.extend(b[0]-a[0] for a,b in zip(distinct,distinct[1:]))
        churn.update(changes([s for _,s in distinct]))
        # Durable store returns newest first.
        archived="".join(reversed(ui["archive"])); archive.update(rating(sample["reference"],archived))
        rows.append(dict(id=i,onset_minus55_s=round(onset,3),last_sustained_signal_s=round(end,3),eof_s=round(ui["endOfFile"],3),
            first_lexical_from_file_s=round(distinct[0][0],3) if distinct else None,
            earliest_reference_bigram_from_file_s=round(matched[0],3) if matched else None,
            reference_bigram_delay_s=round(matched[0]-onset,3) if matched else None,
            pre_eof_lexical_updates=len(distinct),pre_eof_reference_bearing_updates=len(matched),
            pre_onset_lexical_updates=sum(t<onset for t,_ in distinct),
            max_gap_while_audio_continues_s=round(max([min(right,end)-max(left,onset) for left,right in zip([onset]+[t for t,_ in distinct],[t for t,_ in distinct]+[end])]+[0]),3),
            archived_cer=rating(sample["reference"],archived)))
    return dict(samples=len(rows),paired_archived_cer=pooled(archive),first_visible_lexical_after_onset_s=quant(any_delays),
        first_visible_reference_bigram_after_onset_s=quant(delays),first_visible_reference_bigram_from_file_start_s=quant(from_file),
        sources_with_reference_bigram=len(delays),largest_gap_during_active_clip_s=max(r["max_gap_while_audio_continues_s"] for r in rows),ui_lexical_update_gap_s=quant(gaps),ui_tail_churn=dict(churn),
        utterances_ge_10s_with_multiple_reference_bearing_changes=[sum(r["pre_eof_reference_bearing_updates"]>=2 for r in rows if r["eof_s"]>=10),sum(r["eof_s"]>=10 for r in rows)],
        rows=rows)
def critical(item,hyp):
    an=[(a["type"],a["text"],a.get("accepted_forms",[a["text"]])) for a in item["critical"]]+anchors.get(item["id"].split("-")[-1],[])
    return [(typ,key,any(norm(a) in norm(hyp) for a in alts)) for typ,key,alts in an]
def qwen_grid(e,paired):
    ids=[s["id"] for s in paired][:6]; out={}
    for seconds,d in [(0.8,read(e/"qwen-window-0.8.json")),(1.2,read(e/"qwen-small.json")),(2.0,read(e/"qwen-window-2.0.json"))]:
        partials=[];gaps=[];first=[];stats=collections.Counter();final=collections.Counter();words=collections.Counter()
        for i in ids:
            s=next(x for x in d["samples"] if x["id"]==i);ref=norm(s["reference"])
            ev=[x for x in s["events"] if x["kind"]=="partial" and x["t"]<s["eos_s"] and norm(x["text"])]
            if ev:first.append(ev[0]["t"])
            gaps += [b["t"]-a["t"] for a,b in zip(ev,ev[1:])];stats.update(changes([x["text"] for x in ev]))
            # Best matching *prefix* of ref; not CER against time-aligned ground truth.
            for x in ev:
                h=norm(x["text"])
                distances=[(align(ref[:n],h)["errors"],abs(n-len(h))) for n in range(1,len(ref)+1)]
                words["errors"]+=min(distances)[0];words["chars"]+=len(h)
            partials.append(len(ev));final.update(rating(ref,s["events"][-1]["text"]))
        out[str(seconds)]=dict(samples=len(ids),first_worker_text_from_file_s=quant(first),worker_gap_s=quant(gaps),
            total_pre_eof_updates=sum(partials),tail_churn=dict(stats),
            closest_reference_prefix_error_per_output_char=round(words["errors"]/words["chars"],4),final_cer=pooled(final))
    return out
def main():
    p=argparse.ArgumentParser();p.add_argument("--audio",type=pathlib.Path,required=True);p.add_argument("--evidence",type=pathlib.Path,default=ROOT/"evidence/local-asr")
    p.add_argument("--engines",default="candidate-engines");p.add_argument("--panels",default="candidate-panels");p.add_argument("--archive",default="candidate-archive");p.add_argument("--sha",required=True);p.add_argument("--out",type=pathlib.Path,required=True);a=p.parse_args();e=a.evidence
    bundle=e/a.engines/"bundle.json"
    if bundle.exists(): assert read(bundle)["source"]==a.sha
    result=dict(source=a.sha,platform="Apple M5 24 GiB; macOS 27.0 build 26A428; arm64",metric="micro CER: repository NFKC/casefold, punctuation-as-space; do not convert numerals, Chinese scripts or foreign names. Sample nearest-rank quantiles. Latencies in seconds.",
       cohort="10 paired FLEURS zh-CN licensed test WAVs; six primary + four annotated clean challenges. No live microphone or private recordings.",models={})
    ds={m:read((e/a.engines)/f"{m}.json") for m in models}
    refs=ds["sherpa"]["samples"];assert len(refs)==10 and len(set(s["id"] for s in refs))==10
    for m,d in ds.items():
        assert d["status"]=="PASS" and [(x["id"],x["audio_sha256"]) for x in d["samples"]]==[(x["id"],x["audio_sha256"]) for x in refs]
        solved=collections.Counter();tested=collections.Counter();misses=collections.defaultdict(list);final=collections.Counter();eos=[];sample_metrics=[]
        for s in d["samples"]:
            last=s["events"][-1];assert last["kind"]=="final";hyp=last["text"];r=rating(s["reference"],hyp);final.update(r);eos.append(last["t"]-s["eos_s"])
            for typ,key,ok in critical(s,hyp):
                tested[typ]+=1;solved[typ]+=int(ok)
                if not ok: misses[typ].append([s["id"],key])
            sample_metrics.append(dict(id=s["id"],**r))
        resources=d["resources"];rr=dict(bytes=d["weight_bytes"],revision=d["revision"],load_s=d["load_s"],worker_or_apple_client_peak_rss_mib=round(max(v["rss_kib"] for v in resources)/1024,1),
                process_cpu_percent=quant([r["cpu_percent"] for r in resources]),worker_final_after_eos_s=quant(eos),worker_final_cer=pooled(final),
                lexical_anchors={k:{"found":solved[k],"tested":v,"misses":misses[k]} for k,v in tested.items()},error_counts_per_clip=sample_metrics)
        if m in live:rr["native_panel"]=frontend(m,e/a.panels,refs,a.audio,a.sha)
        else:
            subset=sorted((e/a.archive).glob(m+"-*.json"))
            assert len(subset)>=1
            for f in subset:
                x=read(f);assert x["exit_code"]==0 and x["sha"]==a.sha and x["providers"]==[m] and x["archive"] and not any(t["t"]<x["endOfFile"] and t["speaking"] for t in x["frames"])
            rr["archive_only"]=dict(native_archive_success=len(subset),native_first_archive_after_eos_s=[round(x["frames"][0]["t"]-x["endOfFile"],3) for x in map(read,subset)])
        result["models"][m]=rr
    result["qwen_0_6b_paired_window_study"]=qwen_grid(e,refs)
    a.out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
if __name__=="__main__":main()
