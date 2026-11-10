#!/usr/bin/env python3
"""Paced native-worker measurements on hash-checked licensed FLEURS PCM. No microphone or cloud."""
import argparse, hashlib, json, math, pathlib, queue, statistics, struct, subprocess, threading, time, wave
from array import array
from itertools import takewhile

def now():
    return time.monotonic()

def run(args):
    manifests = pathlib.Path("Sources/SaytileKit/Resources/LocalASR")
    corpus = json.loads(pathlib.Path("research/asr-2026-11-06/corpus/manifest.json").read_text())
    items = [i for i in corpus if i.get("source_dataset") == "fleurs-zh" and i["group"] == "primary"][:args.primary]
    if not args.primary_only:
        items += [i for i in corpus if i.get("source_dataset") == "fleurs-zh" and i["group"] != "primary" and not i["synthetic_perturbation"]]
    manifest = json.loads((manifests / (args.model + ".json")).read_text())
    binary = args.runtime.resolve() / ("SaytileSherpa" if args.model in ("sherpa","zipformer") else "SaytileModelWorker")
    directory = args.weights / args.model / manifest["revision"]
    assert all((directory/f["path"]).stat().st_size == f["bytes"] for f in manifest["files"])
    args.output.parent.mkdir(exist_ok=True, parents=True)
    result = dict(model=args.model,revision=manifest["revision"],weight_bytes=sum(f["bytes"] for f in manifest["files"]),
                  worker_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),chunk_seconds=args.chunk, samples=[],resources=[],status="FAIL")
    events = queue.Queue()
    begin = now()
    worker = subprocess.Popen([str(binary),args.model,str(directory.resolve()),str(round(16_000*args.chunk))],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              cwd=(args.runtime.resolve().parent/"Resources") if (args.runtime.resolve().parent/"Resources/default.metallib").exists() else None)
    def read_output():
        for line in worker.stdout:
            try: events.put((now(), json.loads(line)))
            except ValueError: continue
        events.put((now(),dict(kind="exit")))
    threading.Thread(target=read_output, daemon=True).start()
    stop = threading.Event()
    def sample():
        while not stop.wait(.7):
            raw = subprocess.check_output(["ps","-p",str(worker.pid),"-o","rss=,pcpu="]).split()
            if len(raw)==2: result["resources"].append(dict(t=round(now()-begin,3),rss_kib=int(raw[0]),cpu_percent=float(raw[1])))
    threading.Thread(target=sample,daemon=True).start()
    def expect(seconds):
        at,value=events.get(timeout=seconds)
        if value["kind"]=="exit": raise RuntimeError("native worker exited: "+str(worker.poll()))
        return at,value
    try:
        at,msg=expect(90);assert msg["kind"]=="ready"
        result["load_s"]=round(at-begin,3)
        for item in items:
            path=args.audio/item["audio"];assert hashlib.sha256(path.read_bytes()).hexdigest()==item["audio_sha256"]
            with wave.open(str(path)) as wav:
                assert (wav.getframerate(),wav.getnchannels(),wav.getsampwidth())==(16000,1,2)
                pcm=wav.readframes(wav.getnframes())
            # Same onset proxy for all candidates: first 20 ms with RMS >= -40 dBFS.
            sig=array("h",pcm); onset=next((i for i in range(0,len(sig),320) if
                sum(v*v for v in sig[i:i+320]) >= len(sig[i:i+320])*327.68**2),0)/16000
            start=now()
            for pos in range(0,len(pcm),1280):
                time.sleep(max(0,start+min(pos+1280,len(pcm))/32000-now()))
                block=pcm[pos:pos+1280];worker.stdin.write(struct.pack("<I",len(block))+block);worker.stdin.flush()
            eos=now();worker.stdin.write(bytes(4));worker.stdin.flush()
            outputs=[]
            while True:
                at,msg=expect(120)
                outputs.append(dict(t=round(at-start,4),**msg))
                if msg["kind"]=="final":break
            result["samples"].append(dict(id=item["id"],reference=item["reference"],critical=item.get("critical",[]),
                audio_sha256=item["audio_sha256"],duration_s=len(pcm)/32000,onset_s=onset,eos_s=round(eos-start,4),events=outputs))
            args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
        result["status"]="PASS"
    finally:
        stop.set();worker.stdin.close()
        try: worker.wait(timeout=4)
        except subprocess.TimeoutExpired: worker.kill();worker.wait()
        args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
if __name__=="__main__":
    p=argparse.ArgumentParser()
    for flag in ["weights","runtime","audio","output"]:p.add_argument("--"+flag,type=pathlib.Path,required=True)
    p.add_argument("--model",required=True);p.add_argument("--chunk",type=float,default=1.2)
    p.add_argument("--primary",type=int,default=6);p.add_argument("--primary-only",action="store_true")
    run(p.parse_args())
