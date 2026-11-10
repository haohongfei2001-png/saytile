#!/usr/bin/env python3
"""Observe actual AppKit runs of a particular candidate on the paired licensed audio."""
import argparse, hashlib, json, pathlib, shutil, subprocess, tempfile
p=argparse.ArgumentParser()
for name in ["app","weights","audio","out","paired"]:p.add_argument("--"+name,type=pathlib.Path,required=True)
p.add_argument("--models",nargs="+",default=["apple","sherpa","nemotron-metal","qwen-small"])
p.add_argument("--limit",type=int,default=10)
a=p.parse_args()
samples=json.loads(a.paired.read_text())["samples"][:a.limit]
a.out.mkdir(exist_ok=True,parents=True)
for model in a.models:
    with tempfile.TemporaryDirectory(prefix="saytile-local-panels-") as tmp:
        for index,item in enumerate(samples):
            root=pathlib.Path(tmp)/str(index);root.mkdir()
            if model!="apple":
                (root/"LocalModels").mkdir()
                # APFS clone only our approved, hash-pinned model directory.
                subprocess.run(["cp","-cR",str(a.weights/model),str(root/"LocalModels")+"/"],check=True)
            src=a.audio/(item["id"]+".wav")
            assert hashlib.sha256(src.read_bytes()).hexdigest()==item["audio_sha256"]
            shutil.copyfile(src,root/"fixture.wav")
            r=subprocess.run([str(a.app/"Contents/MacOS/Saytile"),"--data-directory",str(root),"--local-stream-probe",model],
                             capture_output=True,text=True,timeout=130)
            receipt=root/"visible.json"
            if not receipt.exists(): raise RuntimeError(model+":"+item["id"]+" "+r.stdout[-350:])
            result=json.loads(receipt.read_text())
            result.update(id=item["id"],audio_sha256=item["audio_sha256"],exit_code=r.returncode)
            (a.out/(model+"-"+item["id"]+".json")).write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
            if index==5 and (root/"partial.png").exists():shutil.copyfile(root/"partial.png",a.out/(model+"-mid-speech.png"))
            shutil.rmtree(root)

