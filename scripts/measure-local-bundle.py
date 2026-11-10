#!/usr/bin/env python3
"""Pace the same licensed speech into a mounted-then-copied candidate. Optional read-only macmon telemetry."""
import argparse, datetime, hashlib, json, os, pathlib, signal, statistics, subprocess, sys, tempfile, time, plistlib
P=pathlib.Path
p=argparse.ArgumentParser()
for k in ("app","weights","audio","output"):p.add_argument("--"+k,type=P,required=True)
p.add_argument("--telemetry",type=P);p.add_argument("--idle-seconds",type=int,default=0);p.add_argument("--primary-only",type=int,default=0)
a=p.parse_args();a.app=a.app.resolve(); output=a.output;output.mkdir(parents=True,exist_ok=True)
meta=plistlib.loads((a.app/"Contents/Info.plist").read_bytes())
assert meta["CFBundleIdentifier"]=="app.saytile.mac" and meta["SaytileSourceDirty"]==False
stamp={"source":meta["SaytileSourceRevision"],"version":meta["SaytileReleaseVersion"],"local_time":datetime.datetime.now(datetime.timezone.utc).isoformat(),
       "system":subprocess.check_output(["sw_vers","-buildVersion"],text=True).strip(),"host_chip":subprocess.check_output(["sysctl","-n","machdep.cpu.brand_string"],text=True).strip()}
if (output/"bundle.json").exists():raise SystemExit("output directory already represents a run")
(output/"bundle.json").write_text(json.dumps(stamp,indent=2)+"\n")
def observed(label,call):
    if not a.telemetry:return call()
    fields=["timestamp","sys_power","cpu_active_ratio","gpu_active_ratio","cpu_power","gpu_power","ane_power"]
    with tempfile.TemporaryFile(mode="w+") as temp:
        meter=subprocess.Popen([str(a.telemetry.resolve()),"pipe","-i","1000"],stdout=temp,stderr=subprocess.DEVNULL)
        try:call()
        finally:
            meter.send_signal(signal.SIGTERM)
            try:meter.wait(timeout=4)
            except subprocess.TimeoutExpired:meter.kill();meter.wait()
            temp.seek(0);vals=[]
            for line in temp:
                try:d=json.loads(line)
                except ValueError:continue
                vals.append({k:d[k] for k in fields})
            (output/(label+"-telemetry.json")).write_text(json.dumps(vals,separators=(",",":"))+"\n")
            if len(vals)<3:raise RuntimeError("no usable system telemetry: "+label)
def run(cmd,label):
    with (output/(label+".stderr")).open("w") as log:subprocess.run(cmd,stdout=log,stderr=log,check=True)
for m in ("sherpa","nemotron-metal","qwen-small","paraformer","sensevoice","qwen-large","apple"):
    if a.idle_seconds:
        observed(m+"-idle",lambda:time.sleep(a.idle_seconds))
    if m=="apple":
        cmd=[sys.executable,"scripts/bench-apple-asr.py","--executable",a.app/"Contents/MacOS/Saytile","--paired",output/"sherpa.json","--audio",a.audio,"--output",output/(m+".json")]
    else:
        cmd=[sys.executable,"scripts/bench-local-asr.py","--runtime",a.app/"Contents/Helpers","--weights",a.weights,"--model",m,"--audio",a.audio,"--output",output/(m+".json")]
        if a.primary_only:cmd+=["--primary",str(a.primary_only),"--primary-only"]
    observed(m,lambda:run(cmd,m))
    if json.loads((output/(m+".json")).read_text())["status"]!="PASS":raise RuntimeError(m)
