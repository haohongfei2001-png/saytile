#!/usr/bin/env python3
"""Publish only device-level numerical telemetry; no process environment, filenames or private events."""
import argparse, json, math, pathlib, statistics
p=argparse.ArgumentParser()
for k in ("input","output"):p.add_argument("--"+k,type=pathlib.Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
load=lambda f:json.loads(f.read_text())
b=load(a.input/"bundle.json");r={"source":b["source"],"cohort":"first two shared FLEURS recordings, paced, fresh process with available system caches; eight seconds idle immediately before each model; numerical power samples every one second",
    "meter":"macmon 0.11.0; macOS IOReport and system power telemetry; unsigned differences include all host activity, not isolated app wattage or battery-life estimates. Handles with no per-process GPU/ANE counter remain unknown.", "models":{}}
keys=["sys_power","cpu_power","gpu_power","ane_power","cpu_active_ratio","gpu_active_ratio"]
def series(stream):
    return {k:{"mean":round(statistics.mean(x[k] for x in stream),4),"p50":round(statistics.median(x[k] for x in stream),4),
               "p95":round(sorted(x[k] for x in stream)[math.ceil(.95*len(stream))-1],4),"max":round(max(x[k] for x in stream),4)} for k in keys}
for m in "apple sherpa nemotron-metal qwen-small paraformer sensevoice qwen-large".split():
    idle=load(a.input/(m+"-idle-telemetry.json"));active=load(a.input/(m+"-telemetry.json"));d=load(a.input/(m+".json"))
    assert d["status"]=="PASS" and len(d["samples"])==2 and len(idle)>=4 and len(active)>=8
    assert all(x["sys_power"]>0 and x["cpu_power"]>=0 and x["gpu_power"]>=0 and x["ane_power"]>=0 for x in idle+active)
    i,s=series(idle),series(active)
    r["models"][m]={"idle_sample_count":len(idle),"active_sample_count":len(active),"idle":i,"active":s,"mean_system_w_difference":round(s["sys_power"]["mean"]-i["sys_power"]["mean"],3)}
    payload=dict(source=b["source"],model=m,samples=[x["id"] for x in d["samples"]],idle=idle,active=active)
    (a.output/(m+".json")).write_text(json.dumps(payload,separators=(",",":"))+"\n")
(a.output/"summary.json").write_text(json.dumps(r,indent=2)+"\n")
