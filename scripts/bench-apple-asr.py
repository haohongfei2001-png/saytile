#!/usr/bin/env python3
"""Exercise Apple's production SpeechAnalyzer on the same paired WAVs as the external workers."""
import argparse, hashlib, json, pathlib, re, subprocess, tempfile, time
from threading import Thread
p=argparse.ArgumentParser()
for key in ["executable","paired","audio","output"]: p.add_argument("--"+key,type=pathlib.Path,required=True)
args=p.parse_args()
base=json.loads(args.paired.read_text())
result=dict(model="apple",revision=subprocess.check_output(["sw_vers","-buildVersion"],text=True).strip(),
            weight_bytes=None,load_s=None,samples=[],resources=[],status="FAIL")
with tempfile.TemporaryDirectory(prefix="saytile-local-apple-") as tmp:
    for index,paired in enumerate(base["samples"]):
        wav=args.audio/(paired["id"]+".wav"); assert hashlib.sha256(wav.read_bytes()).hexdigest()==paired["audio_sha256"]
        proc=subprocess.Popen([str(args.executable.resolve()),"--data-directory",tmp+"/"+str(index),"--audio-probe",str(wav.resolve()),"--paced"],
                              stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
        def sample():
            while proc.poll() is None:
                raw=subprocess.run(["ps","-p",str(proc.pid),"-o","rss=,pcpu="],capture_output=True,text=True).stdout.split()
                if len(raw)==2: result["resources"].append(dict(rss_kib=int(raw[0]),cpu_percent=float(raw[1])))
                time.sleep(.8)
        t=Thread(target=sample,daemon=True);t.start()
        try: out=proc.communicate(timeout=100)[0]
        except subprocess.TimeoutExpired: proc.kill();proc.wait();raise
        t.join()
        events=[json.loads(s.removeprefix("LOCAL_TIMING ")) for s in out.splitlines() if s.startswith("LOCAL_TIMING ")]
        match=re.search(r"^SPEECH_RESULT completed (.*?) error=none$",out,re.M)
        if not match: raise RuntimeError(out[:1000])
        end=next(e["elapsedSeconds"] for e in events if e["kind"]=="inputFinished")
        final=next(e["elapsedSeconds"] for e in events if e["kind"]=="completed")
        if index==0: result["load_s"]=next(e["elapsedSeconds"] for e in events if e["kind"]=="prepared")
        sample={k:v for k,v in paired.items() if k not in ("events","eos_s")}
        sample.update(eos_s=end,events=[dict(kind="partial",text=e["text"],t=e["elapsedSeconds"]) for e in events if e["kind"]=="preview"]
                      +[dict(kind="final",text=match[1],t=final)])
        result["samples"].append(sample)
        args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
result["status"]="PASS"
args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
